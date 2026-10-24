import Darwin
import Foundation

// shortcut: IPv4 only, add a second socket family when a device needs IPv6
struct IPv4Peer: Equatable {
    var address: UInt32
    var port: UInt16

    var ipString: String {
        var addr = in_addr(s_addr: address)
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &addr, &buffer, socklen_t(buffer.count))
        return String(cString: buffer)
    }

    static func resolve(host: String, port: UInt16) -> IPv4Peer? {
        var address = in_addr()
        if inet_pton(AF_INET, host, &address) == 1 {
            return IPv4Peer(address: address.s_addr, port: port)
        }
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &info) == 0, let info else { return nil }
        defer { freeaddrinfo(info) }
        var peer: IPv4Peer?
        info.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer in
            peer = IPv4Peer(address: pointer.pointee.sin_addr.s_addr, port: port)
        }
        return peer
    }
}

struct UDPError: Error, CustomStringConvertible {
    let description: String
}

final class UDPSocket: @unchecked Sendable {
    private var fd: Int32 = -1
    private let lock = NSLock()

    init(port: UInt16) throws {
        let opened = socket(AF_INET, SOCK_DGRAM, 0)
        if opened < 0 {
            throw UDPError(description: "无法创建 UDP 套接字：\(Self.errnoText())")
        }
        var reuse: Int32 = 1
        setsockopt(opened, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse)))
        let flags = fcntl(opened, F_GETFL)
        if flags >= 0 {
            _ = fcntl(opened, F_SETFL, flags | O_NONBLOCK)
        }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = in_addr(s_addr: in_addr_t(INADDR_ANY))
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(opened, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bound != 0 {
            let message = errno == EACCES || errno == EPERM
                ? "端口 \(port) 需要管理员权限或已被占用"
                : "无法绑定 UDP 端口 \(port)：\(Self.errnoText())"
            Darwin.close(opened)
            throw UDPError(description: message)
        }
        fd = opened
    }

    deinit { close() }

    func localPort() -> UInt16 {
        guard let current = currentFD() else { return 0 }
        var addr = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(current, $0, &length)
            }
        }
        return result == 0 ? UInt16(bigEndian: addr.sin_port) : 0
    }

    func send(_ data: Data, to peer: IPv4Peer) throws {
        guard let current = currentFD() else { throw UDPError(description: "套接字已关闭") }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = peer.port.bigEndian
        addr.sin_addr = in_addr(s_addr: peer.address)
        var dummy: UInt8 = 0
        let sent = withUnsafePointer(to: &addr) { addressPointer -> Int in
            addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                if data.isEmpty {
                    return Darwin.sendto(current, &dummy, 0, 0, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
                return data.withUnsafeBytes { raw in
                    Darwin.sendto(current, raw.baseAddress, data.count, 0, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        if sent < 0 {
            throw UDPError(description: "UDP 发送失败：\(Self.errnoText())")
        }
    }

    func receive(timeout: TimeInterval) -> (Data, IPv4Peer)? {
        guard let current = currentFD() else { return nil }
        var descriptor = pollfd(fd: current, events: Int16(POLLIN), revents: 0)
        let milliseconds = Int32((max(0, timeout) * 1000).rounded())
        if poll(&descriptor, 1, milliseconds) <= 0 { return nil }
        if descriptor.revents & Int16(POLLNVAL | POLLERR | POLLHUP) != 0 { return nil }
        var buffer = [UInt8](repeating: 0, count: 65536)
        var addr = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let count = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                recvfrom(current, &buffer, buffer.count, 0, $0, &length)
            }
        }
        if count < 0 { return nil }
        let peer = IPv4Peer(address: addr.sin_addr.s_addr, port: UInt16(bigEndian: addr.sin_port))
        return (Data(buffer.prefix(count)), peer)
    }

    func close() {
        lock.lock()
        let current = fd
        fd = -1
        lock.unlock()
        if current >= 0 { Darwin.close(current) }
    }

    private func currentFD() -> Int32? {
        lock.lock()
        let current = fd
        lock.unlock()
        return current >= 0 ? current : nil
    }

    private static func errnoText() -> String {
        String(cString: strerror(errno))
    }
}
