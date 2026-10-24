import Foundation

enum TFTPBlocks {
    static func number(forIndex index: Int) -> UInt16 {
        UInt16(truncatingIfNeeded: index &+ 1)
    }

    /// Bytes to send for this block. nil means the file has already ended.
    /// Zero is the empty packet that finishes a file whose size is a multiple of `blksize`.
    static func length(fileSize: Int64, index: Int, blksize: Int) -> Int? {
        guard blksize > 0, index >= 0 else { return nil }
        let offset = Int64(index) * Int64(blksize)
        if offset > fileSize { return nil }
        if offset == fileSize {
            return fileSize % Int64(blksize) == 0 ? 0 : nil
        }
        return Int(min(Int64(blksize), fileSize - offset))
    }
}

enum TFTPPackets {
    static func request(opcode: UInt16, filename: String, options: [(String, String)]) -> Data {
        var packet = Data([UInt8(opcode >> 8), UInt8(opcode & 0xFF)])
        append(filename, to: &packet)
        append("octet", to: &packet)
        for (name, value) in options {
            append(name, to: &packet)
            append(value, to: &packet)
        }
        return packet
    }

    static func data(block: UInt16, payload: Data) -> Data {
        var packet = Data([0x00, 0x03, UInt8(block >> 8), UInt8(block & 0xFF)])
        packet.append(payload)
        return packet
    }

    static func ack(_ block: UInt16) -> Data {
        Data([0x00, 0x04, UInt8(block >> 8), UInt8(block & 0xFF)])
    }

    static func oack(_ options: [(String, String)]) -> Data {
        var packet = Data([0x00, 0x06])
        for (name, value) in options {
            append(name, to: &packet)
            append(value, to: &packet)
        }
        return packet
    }

    static func error(code: UInt16, message: String) -> Data {
        var packet = Data([0x00, 0x05, UInt8(code >> 8), UInt8(code & 0xFF)])
        append(message, to: &packet)
        return packet
    }

    static func opcode(of data: Data) -> UInt16? {
        guard data.count >= 2 else { return nil }
        return UInt16(data[0]) << 8 | UInt16(data[1])
    }

    static func block(of data: Data) -> UInt16? {
        guard data.count >= 4 else { return nil }
        return UInt16(data[2]) << 8 | UInt16(data[3])
    }

    static func payload(of data: Data) -> Data {
        data.count > 4 ? data.subdata(in: 4..<data.count) : Data()
    }

    static func strings(in bytes: any Sequence<UInt8>) -> [String] {
        var strings: [String] = []
        var current = Data()
        for byte in bytes {
            if byte == 0 {
                if let text = String(data: current, encoding: .utf8) ?? String(data: current, encoding: .isoLatin1) {
                    strings.append(text)
                }
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(byte)
            }
        }
        return strings
    }

    static func requestFields(_ data: Data) -> (filename: String, mode: String, options: [String: String])? {
        guard opcode(of: data) != nil else { return nil }
        let fields = strings(in: data.dropFirst(2))
        let filename = fields.indices.contains(0) ? fields[0] : ""
        let mode = fields.indices.contains(1) ? fields[1].lowercased() : "octet"
        var options: [String: String] = [:]
        var index = 2
        while index + 1 < fields.count {
            options[fields[index].lowercased()] = fields[index + 1]
            index += 2
        }
        return (filename, mode, options)
    }

    static func errorMessage(_ data: Data) -> String {
        let fields = strings(in: data.dropFirst(min(4, data.count)))
        if let message = fields.first, !message.isEmpty { return message }
        return "TFTP 错误"
    }

    static func isOctet(_ mode: String) -> Bool {
        let value = mode.lowercased()
        return value == "octet" || value == "binary"
    }

    static func acceptedOptions(_ options: [String: String], fileSize: Int64, isRead: Bool) -> [(String, String)] {
        var accepted: [(String, String)] = []
        if let raw = options["blksize"], let size = Int(raw), (8...65464).contains(size) {
            accepted.append(("blksize", String(size)))
        }
        if let raw = options["timeout"], let seconds = Int(raw), (1...255).contains(seconds) {
            accepted.append(("timeout", String(seconds)))
        }
        if options["tsize"] != nil {
            accepted.append(("tsize", isRead ? String(fileSize) : "0"))
        }
        return accepted
    }

    static func blksize(in options: [(String, String)], fallback: Int) -> Int {
        guard let raw = options.first(where: { $0.0 == "blksize" })?.1, let size = Int(raw) else { return fallback }
        return size
    }

    static func timeout(in options: [(String, String)], fallback: Int) -> Int {
        guard let raw = options.first(where: { $0.0 == "timeout" })?.1, let seconds = Int(raw) else { return fallback }
        return seconds
    }

    private static func append(_ text: String, to packet: inout Data) {
        if let bytes = text.data(using: .utf8) {
            packet.append(bytes)
        }
        packet.append(0)
    }
}

enum TFTPFiles {
    /// Reads exactly `count` bytes, or fewer only at EOF. One `read` can return early.
    static func read(_ handle: FileHandle?, count: Int) throws -> Data {
        guard let handle else {
            throw NSError(domain: "TFTP", code: 1, userInfo: [NSLocalizedDescriptionKey: "文件未打开"])
        }
        if count == 0 { return Data() }
        var data = Data()
        data.reserveCapacity(count)
        while data.count < count {
            let chunk = try handle.read(upToCount: count - data.count) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        return data
    }
}
