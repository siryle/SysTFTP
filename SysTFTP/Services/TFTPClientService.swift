import Foundation

public protocol TFTPClientDelegate: AnyObject {
    func tftpClientDidLog(_ message: String, isError: Bool)
    func tftpClientProgressUpdated(bytesTransferred: Int64, totalBytes: Int64?, speedBytesPerSec: Double, progress: Double)
    func tftpClientDidComplete(success: Bool, message: String)
}

public final class TFTPClientService {
    public weak var delegate: TFTPClientDelegate?

    private let queue = DispatchQueue(label: "com.systftp.client.tftp", qos: .userInitiated)
    private let stateLock = NSLock()
    private var socket: UDPSocket?
    private var runToken = 0
    private var finishedToken = 0

    public init() {}

    public func startTransfer(config: TFTPClientConfig) {
        let token = beginRun()
        queue.async { [weak self] in self?.run(config, token: token) }
    }

    public func cancel() {
        stateLock.lock()
        runToken += 1
        let opened = socket
        stateLock.unlock()
        opened?.close()
    }

    private func beginRun() -> Int {
        stateLock.lock()
        runToken += 1
        let token = runToken
        let opened = socket
        stateLock.unlock()
        opened?.close()
        return token
    }

    private func isCurrent(_ token: Int) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return runToken == token
    }

    private func run(_ config: TFTPClientConfig, token: Int) {
        guard isCurrent(token) else { return }
        guard (1...65535).contains(config.serverPort) else {
            complete(false, "无效端口号：\(config.serverPort)", token: token)
            return
        }
        guard TFTPPackets.isOctet(config.mode) else {
            complete(false, "仅支持二进制（octet）传输", token: token)
            return
        }
        guard let peerAddress = IPv4Peer.resolve(host: config.serverHost, port: UInt16(config.serverPort)) else {
            complete(false, "无法解析服务器地址：\(config.serverHost)", token: token)
            return
        }
        let socket: UDPSocket
        do {
            socket = try UDPSocket(port: 0)
        } catch {
            complete(false, error.localizedDescription, token: token)
            return
        }
        stateLock.lock()
        if !isCurrentLocked(token) {
            stateLock.unlock()
            socket.close()
            return
        }
        self.socket = socket
        stateLock.unlock()
        delegate?.tftpClientDidLog("已连接到 TFTP 服务器 \(config.serverHost):\(config.serverPort)", isError: false)

        let transfer = ClientTransfer(config: config, socket: socket, server: peerAddress, delegate: delegate)
        transfer.onCancel = { [weak self] in self?.isCurrent(token) == false }
        transfer.run()
        stateLock.lock()
        if self.socket === socket { self.socket = nil }
        stateLock.unlock()
        if transfer.endedSilently == false, let result = transfer.result {
            complete(result.success, result.message, token: token)
        }
    }

    private func isCurrentLocked(_ token: Int) -> Bool {
        runToken == token
    }

    private func complete(_ success: Bool, _ message: String, token: Int) {
        stateLock.lock()
        if finishedToken == token || runToken != token {
            stateLock.unlock()
            return
        }
        finishedToken = token
        let opened = socket
        socket = nil
        stateLock.unlock()
        opened?.close()
        delegate?.tftpClientDidComplete(success: success, message: message)
    }
}

private final class ClientTransfer {
    struct Result { let success: Bool; let message: String }
    var result: Result?
    var endedSilently = false
    var onCancel: () -> Bool = { false }

    private let config: TFTPClientConfig
    private let socket: UDPSocket
    private var server: IPv4Peer
    private let delegate: TFTPClientDelegate?
    private var tidLocked = false
    private var blksize: Int
    private var timeoutSeconds: Int
    private let maxRetries: Int
    private var retries = 0
    private var blockIndex = 0
    private var lastLength = 0
    private var lastPacket = Data()
    private var fileSize: Int64 = 0
    private var transferred: Int64 = 0
    private var reader: FileHandle?
    private var writer: FileHandle?
    private var partialURL: URL?
    private let started = Date()
    private var sawOptions = false

    init(config: TFTPClientConfig, socket: UDPSocket, server: IPv4Peer, delegate: TFTPClientDelegate?) {
        self.config = config
        self.socket = socket
        self.server = server
        self.delegate = delegate
        blksize = config.enableBlockSizeNegotiation ? min(65464, max(8, config.blockSize)) : 512
        timeoutSeconds = min(255, max(1, config.timeoutSeconds))
        maxRetries = 10
    }

    func run() {
        do {
            if config.isUpload {
                let attrs = try FileManager.default.attributesOfItem(atPath: config.localFilePath)
                fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
                reader = try FileHandle(forReadingFrom: URL(fileURLWithPath: config.localFilePath))
            } else {
                let destination = URL(fileURLWithPath: config.localFilePath)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                partialURL = destination.appendingPathExtension("part")
                if let partialURL {
                    FileManager.default.createFile(atPath: partialURL.path, contents: nil)
                    writer = try FileHandle(forWritingTo: partialURL)
                }
            }
        } catch {
            result = Result(success: false, message: "无法打开本地文件：\(error.localizedDescription)")
            return
        }

        var options: [(String, String)] = []
        if config.enableBlockSizeNegotiation { options.append(("blksize", String(blksize))) }
        if config.enableTimeoutNegotiation { options.append(("timeout", String(timeoutSeconds))) }
        if config.enableTransferSizeNegotiation { options.append(("tsize", config.isUpload ? String(fileSize) : "0")) }
        sawOptions = !options.isEmpty
        lastPacket = TFTPPackets.request(opcode: config.isUpload ? 2 : 1, filename: config.remoteFilePath, options: options)
        delegate?.tftpClientDidLog(config.isUpload ? "正在请求上传 '\(config.remoteFilePath)'（\(fileSize) 字节）…" : "正在请求下载 '\(config.remoteFilePath)'…", isError: false)
        guard transmit(lastPacket) else { return }

        while result == nil {
            if onCancel() {
                endedSilently = true
                cleanup(success: false)
                return
            }
            guard let (data, from) = socket.receive(timeout: TimeInterval(timeoutSeconds)) else {
                if onCancel() { endedSilently = true; cleanup(success: false); return }
                timedOut()
                continue
            }
            if !tidLocked {
                guard from.address == server.address else { continue }
                server.port = from.port
                tidLocked = true
            } else if from != server {
                continue
            }
            handle(data)
        }
        cleanup(success: result?.success == true)
    }

    private func handle(_ data: Data) {
        guard let opcode = TFTPPackets.opcode(of: data) else { return }
        switch opcode {
        case 3: handleData(data)
        case 4: handleAck(data)
        case 5: result = Result(success: false, message: "服务器错误：\(TFTPPackets.errorMessage(data))")
        case 6: handleOACK(data)
        default: result = Result(success: false, message: "意外的操作码：\(opcode)")
        }
    }

    private func handleOACK(_ data: Data) {
        let fields = TFTPPackets.strings(in: data.dropFirst(2))
        var options: [String: String] = [:]
        var index = 0
        while index + 1 < fields.count {
            options[fields[index].lowercased()] = fields[index + 1]
            index += 2
        }
        if let size = options["blksize"].flatMap(Int.init) { blksize = size }
        if let seconds = options["timeout"].flatMap(Int.init) { timeoutSeconds = seconds }
        if let size = options["tsize"].flatMap(Int64.init), !config.isUpload { fileSize = size }
        delegate?.tftpClientDidLog("服务器已接受协商选项：\(options)", isError: false)
        retries = 0
        sawOptions = false
        if config.isUpload {
            _ = sendBlock(index: 0)
        } else {
            lastPacket = TFTPPackets.ack(0)
            _ = transmit(lastPacket)
        }
    }

    private func handleData(_ data: Data) {
        guard !config.isUpload, let block = TFTPPackets.block(of: data) else { return }
        let payload = TFTPPackets.payload(of: data)
        if payload.count > blksize {
            result = Result(success: false, message: "服务器发送的数据块超过协商大小")
            return
        }
        let expected = TFTPBlocks.number(forIndex: blockIndex)
        if block != expected {
            if blockIndex > 0 && block == TFTPBlocks.number(forIndex: blockIndex - 1) {
                _ = transmit(lastPacket)
            }
            return
        }
        do {
            try writer?.write(contentsOf: payload)
        } catch {
            result = Result(success: false, message: "文件保存到磁盘失败：\(error.localizedDescription)")
            return
        }
        transferred += Int64(payload.count)
        retries = 0
        lastPacket = TFTPPackets.ack(block)
        _ = transmit(lastPacket)
        notify()
        if payload.count < blksize {
            result = Result(success: true, message: "下载完成：已将 \(transferred) 字节保存至 \(URL(fileURLWithPath: config.localFilePath).lastPathComponent)")
        } else {
            blockIndex += 1
        }
    }

    private func handleAck(_ data: Data) {
        guard config.isUpload, let ack = TFTPPackets.block(of: data) else { return }
        if ack == 0 && blockIndex == 0 && lastLength == 0 && (sawOptions || !lastPacket.starts(with: Data([0x00, 0x03]))) {
            retries = 0
            sawOptions = false
            _ = sendBlock(index: 0)
            return
        }
        guard ack == TFTPBlocks.number(forIndex: blockIndex) else { return }
        retries = 0
        transferred = min(fileSize, Int64(blockIndex) * Int64(blksize) + Int64(lastLength))
        notify()
        if lastLength < blksize {
            result = Result(success: true, message: "上传完成（已发送 \(transferred) 字节）")
            return
        }
        blockIndex += 1
        _ = sendBlock(index: blockIndex)
    }

    @discardableResult
    private func sendBlock(index: Int) -> Bool {
        guard let length = TFTPBlocks.length(fileSize: fileSize, index: index, blksize: blksize) else {
            result = Result(success: true, message: "上传完成（已发送 \(fileSize) 字节）")
            return false
        }
        do {
            let payload: Data
            if length == 0 {
                payload = Data()
            } else {
                try reader?.seek(toOffset: UInt64(index) * UInt64(blksize))
                payload = try TFTPFiles.read(reader, count: length)
            }
            guard payload.count == length else {
                result = Result(success: false, message: "读取本地文件失败：文件在传输中被截断")
                return false
            }
            lastLength = payload.count
            blockIndex = index
            lastPacket = TFTPPackets.data(block: TFTPBlocks.number(forIndex: index), payload: payload)
            notify()
            return transmit(lastPacket)
        } catch {
            result = Result(success: false, message: "读取本地文件失败：\(error.localizedDescription)")
            return false
        }
    }

    private func timedOut() {
        retries += 1
        if retries > maxRetries {
            result = Result(success: false, message: "等待服务器响应超时")
            return
        }
        _ = transmit(lastPacket)
    }

    @discardableResult
    private func transmit(_ packet: Data) -> Bool {
        do {
            try socket.send(packet, to: server)
            return true
        } catch {
            result = Result(success: false, message: "发送失败：\(error.localizedDescription)")
            return false
        }
    }

    private func notify() {
        let elapsed = max(0.001, Date().timeIntervalSince(started))
        let speed = Double(transferred) / elapsed
        let total = fileSize > 0 ? fileSize : nil
        let progress = total.map { min(1, Double(transferred) / Double($0)) } ?? 0
        delegate?.tftpClientProgressUpdated(bytesTransferred: transferred, totalBytes: total, speedBytesPerSec: speed, progress: progress)
    }

    private func cleanup(success: Bool) {
        try? reader?.close()
        try? writer?.close()
        guard let partialURL else { return }
        let destination = URL(fileURLWithPath: config.localFilePath)
        if success {
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    _ = try FileManager.default.replaceItemAt(destination, withItemAt: partialURL)
                } else {
                    try FileManager.default.moveItem(at: partialURL, to: destination)
                }
            } catch {
                try? FileManager.default.removeItem(at: partialURL)
                result = Result(success: false, message: "文件保存到磁盘失败：\(error.localizedDescription)")
            }
        } else {
            try? FileManager.default.removeItem(at: partialURL)
        }
    }
}
