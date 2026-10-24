import Foundation
import Network

#if canImport(Darwin)
import Darwin
#endif

public final class NetworkMonitorService: ObservableObject {
    public static let shared = NetworkMonitorService()
    
    @Published public var interfaces: [NetworkInterfaceInfo] = []
    @Published public var primaryIP: String = "127.0.0.1"
    
    private var timer: Timer?
    private var preferredInterfaceName: String?
    private let pathMonitor = NWPathMonitor()
    private let ipLock = NSLock()
    private var cachedPrimaryIP = "127.0.0.1"

    public func currentPrimaryIP() -> String {
        ipLock.lock()
        defer { ipLock.unlock() }
        return cachedPrimaryIP
    }
    
    public init() {
        let start = { [weak self] in
            guard let self else { return }
            self.pathMonitor.pathUpdateHandler = { [weak self] path in
                self?.preferredInterfaceName = path.availableInterfaces.first?.name
                self?.refreshInterfaces()
            }
            self.pathMonitor.start(queue: .main)
            self.refreshInterfaces()
            self.startMonitoring()
        }
        if Thread.isMainThread { start() } else { DispatchQueue.main.async(execute: start) }
    }
    
    public func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refreshInterfaces()
        }
    }
    
    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    public func refreshInterfaces() {
        var results: [NetworkInterfaceInfo] = []
        
        #if canImport(Darwin)
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return
        }
        defer { freeifaddrs(ifaddr) }
        
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee
            
            // Check for IPv4
            if addr.sa_family == UInt8(AF_INET) {
                // Check if interface is UP
                let isUp = (flags & IFF_UP) == IFF_UP
                let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK
                
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                var sa = ptr.pointee.ifa_addr.pointee
                getnameinfo(&sa, socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                            &hostname, socklen_t(hostname.count),
                            nil, socklen_t(0), NI_NUMERICHOST)
                
                let ip = String(cString: hostname)
                let name = String(cString: ptr.pointee.ifa_name)
                
                if !ip.isEmpty && !results.contains(where: { $0.ipAddress == ip }) {
                    results.append(NetworkInterfaceInfo(
                        name: name,
                        ipAddress: ip,
                        isUp: isUp,
                        isLoopback: isLoopback
                    ))
                }
            }
        }
        #else
        // Fallback for non-Darwin environments
        results.append(NetworkInterfaceInfo(name: "en0", ipAddress: "192.168.1.100", isUp: true, isLoopback: false))
        results.append(NetworkInterfaceInfo(name: "lo0", ipAddress: "127.0.0.1", isUp: true, isLoopback: true))
        #endif
        
        let usable = results.filter { $0.isUp && !$0.isLoopback }
        let chosen = usable.first(where: { $0.name == self.preferredInterfaceName })
            ?? usable.first(where: { $0.name.hasPrefix("en") })
            ?? usable.first
        let ip = chosen?.ipAddress ?? "127.0.0.1"
        ipLock.lock()
        cachedPrimaryIP = ip
        ipLock.unlock()
        let publish = {
            self.interfaces = results
            self.primaryIP = ip
        }
        if Thread.isMainThread {
            publish()
        } else {
            DispatchQueue.main.async(execute: publish)
        }
    }
}
