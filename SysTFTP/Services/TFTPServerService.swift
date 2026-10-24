import Foundation

public protocol TFTPServerDelegate: AnyObject {
    func tftpServerDidLog(_ message: String, isError: Bool)
    func tftpServerTransferUpdated(_ item: TFTPTransferItem)
    func tftpServerStatusChanged(isRunning: Bool, port: Int)
}

public final class TFTPServerService {
    public weak var delegate: TFTPServerDelegate?
    public private(set) var listeningPort: Int = 0

    private var config: TFTPServerConfig
    private let queue = DispatchQueue(label: "com.systftp.server.tftp", qos: .userInitiated)
    private let lock = NSLock()
    private var socket: UDPSocket?
    private var generation = 0
    private var sessions: [String: TFTPSession] = [:]

    public init(config: TFTPServerConfig = TFTPServerConfig()) {
        self.config = config
    }

    public func updateConfig(_ config: TFTPServerConfig) {
        lock.lock()
        var config = config
        if socket != nil { config.port = self.config.port }
        self.config = config
        lock.unlock()
    }

    public func start() throws {
        stop()
        guard (0...65535).contains(config.port) else {
            throw UDPError(description: "无效端口号：\(config.port)")
        }
        let rootURL = URL(fileURLWithPath: config.rootDirectory)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let opened = try UDPSocket(port: UInt16(config.port))
        let port = Int(opened.localPort())
        lock.lock()
        generation += 1
        let token = generation
        socket = opened
        listeningPort = port
        lock.unlock()
        delegate?.tftpServerDidLog("TFTP 服务正在监听 UDP 端口 \(port)，根目录：\(config.rootDirectory)", isError: false)
        delegate?.tftpServerStatusChanged(isRunning: true, port: port)
        queue.async { [weak self] in self?.acceptLoop(token) }
    }

    public func stop() {
        lock.lock()
        generation += 1
        let opened = socket
        socket = nil
        listeningPort = 0
        let active = Array(sessions.values)
        sessions.removeAll()
        let port = config.port
        lock.unlock()
        opened?.close()
        active.forEach { $0.cancel() }
        guard opened != nil else { return }
        delegate?.tftpServerDidLog("TFTP 服务已停止。", isError: false)
        delegate?.tftpServerStatusChanged(isRunning: false, port: port)
    }

    private func acceptLoop(_ token: Int) {
        while true {
            lock.lock()
            let current = generation == token ? socket : nil
            let activeConfig = config
            lock.unlock()
            guard let current else { return }
            guard let (data, peer) = current.receive(timeout: 0.5) else { continue }
            handle(data, from: peer, config: activeConfig)
        }
    }

    private func handle(_ data: Data, from peer: IPv4Peer, config: TFTPServerConfig) {
        guard let opcode = TFTPPackets.opcode(of: data), opcode == 1 || opcode == 2 else { return }
        let key = "\(peer.ipString):\(peer.port)"
        lock.lock()
        let exists = sessions[key] != nil
        lock.unlock()
        if exists { return }
        guard let request = TFTPPackets.requestFields(data) else { return }
        let direction: TFTPTransferDirection = opcode == 1 ? .download : .upload
        delegate?.tftpServerDidLog(
            "TFTP \(direction == .download ? "下载" : "上传")请求：'\(request.filename)'，客户端 \(key)，模式=\(request.mode)，选项=\(request.options)",
            isError: false
        )
        guard TFTPPackets.isOctet(request.mode) else {
            replyError(5, "Only octet mode is supported", to: peer)
            return
        }
        guard let fileURL = safeFileURL(request.filename, config: config) else {
            replyError(2, "Access violation", to: peer)
            return
        }
        if direction == .download && !FileManager.default.fileExists(atPath: fileURL.path) {
            replyError(1, "File not found", to: peer)
            delegate?.tftpServerDidLog("TFTP 文件不存在：\(request.filename)", isError: true)
            return
        }
        if direction == .upload && FileManager.default.fileExists(atPath: fileURL.path) && !config.allowOverwrite {
            replyError(6, "File already exists", to: peer)
            delegate?.tftpServerDidLog("TFTP 已阻止覆盖文件：\(request.filename)", isError: true)
            return
        }
        if direction == .upload && config.allowCreateDir {
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        let session: TFTPSession
        do {
            session = try TFTPSession(
                key: key,
                peer: peer,
                filename: request.filename,
                fileURL: fileURL,
                direction: direction,
                options: request.options,
                config: config,
                onUpdate: { [weak self] item in self?.delegate?.tftpServerTransferUpdated(item) },
                onFinish: { [weak self] item in
                    self?.lock.lock()
                    self?.sessions.removeValue(forKey: key)
                    self?.lock.unlock()
                    self?.delegate?.tftpServerTransferUpdated(item)
                    let verb = item.direction == .download ? "下载" : "上传"
                    let failed = item.status == .failed || item.status == .aborted
                    self?.delegate?.tftpServerDidLog(
                        failed ? "TFTP \(verb)失败：\(item.filename)（\(item.errorMessage ?? item.status.displayName)）" : "TFTP \(verb)完成：\(item.filename)（\(item.bytesTransferred) 字节）",
                        isError: failed
                    )
                }
            )
        } catch {
            replyError(0, "Unable to start transfer", to: peer)
            delegate?.tftpServerDidLog("TFTP 无法开始传输：\(error.localizedDescription)", isError: true)
            return
        }
        lock.lock()
        if generation == 0 || socket == nil {
            lock.unlock()
            session.cancel()
            return
        }
        sessions[key] = session
        lock.unlock()
        session.start()
    }

    private func safeFileURL(_ filename: String, config: TFTPServerConfig) -> URL? {
        let clean = filename.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !clean.isEmpty, !clean.contains(".."), !clean.contains("\0") else { return nil }
        let lower = clean.lowercased()
        if lower == "3cdaemon.ini" || lower == "profiles.ftp" || lower == "noaccess.ftp" || lower.hasSuffix(".plist") {
            return nil
        }
        guard let path = PathJail.resolve(root: config.rootDirectory, relative: clean) else { return nil }
        return URL(fileURLWithPath: path)
    }

    private func replyError(_ code: UInt16, _ message: String, to peer: IPv4Peer) {
        guard let reply = try? UDPSocket(port: 0) else { return }
        try? reply.send(TFTPPackets.error(code: code, message: message), to: peer)
        reply.close()
    }
}

private final class TFTPSession {
    let key: String
    let filename: String
    let fileURL: URL
    let direction: TFTPTransferDirection
    let onUpdate: (TFTPTransferItem) -> Void
    let onFinish: (TFTPTransferItem) -> Void
    let socket: UDPSocket
    let peer: IPv4Peer
    let queue = DispatchQueue(label: "com.systftp.tftp.session", qos: .userInitiated)
    let transferID = UUID()
    let frameGapMs: Int
    let maxRetries: Int
    var timeoutSeconds: Int
    var blksize: Int
    var fileSize: Int64
    var blockIndex = 0
    var retries = 0
    var lastPacket = Data()
    var lastLength = 0
    var waitingForOptionAck = false
    var finished = false
    var reader: FileHandle?
    var writer: FileHandle?
    var partialURL: URL?
    let stateLock = NSLock()

    init(key: String, peer: IPv4Peer, filename: String, fileURL: URL, direction: TFTPTransferDirection, options: [String: String], config: TFTPServerConfig, onUpdate: @escaping (TFTPTransferItem) -> Void, onFinish: @escaping (TFTPTransferItem) -> Void) throws {
        self.key = key
        self.peer = peer
        self.filename = filename
        self.fileURL = fileURL
        self.direction = direction
        self.onUpdate = onUpdate
        self.onFinish = onFinish
        self.frameGapMs = max(0, config.frameGapMs)
        self.maxRetries = max(0, config.maxRetries)
        self.timeoutSeconds = min(255, max(1, config.timeoutSeconds))
        self.blksize = 512
        socket = try UDPSocket(port: 0)
        if direction == .download {
            let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            reader = try FileHandle(forReadingFrom: fileURL)
        } else {
            fileSize = Int64(options["tsize"] ?? "") ?? 0
            let partial = fileURL.appendingPathExtension("part")
            partialURL = partial
            FileManager.default.createFile(atPath: partial.path, contents: nil)
            writer = try FileHandle(forWritingTo: partial)
        }
        let accepted = TFTPPackets.acceptedOptions(options, fileSize: fileSize, isRead: direction == .download)
        if !accepted.isEmpty {
            blksize = TFTPPackets.blksize(in: accepted, fallback: blksize)
            timeoutSeconds = TFTPPackets.timeout(in: accepted, fallback: timeoutSeconds)
            waitingForOptionAck = direction == .download
            lastPacket = TFTPPackets.oack(accepted)
        }
    }

    func start() {
        guard !isFinished else { return }
        publish(.inProgress)
        queue.async { [weak self] in self?.run() }
    }

    func cancel() {
        complete(.aborted, message: "已取消")
    }

    private func run() {
        if isFinished { return }
        if !waitingForOptionAck && lastPacket.isEmpty {
            if direction == .download {
                guard sendBlock(index: 0) else { return }
            } else {
                send(TFTPPackets.ack(0))
            }
        } else if !lastPacket.isEmpty {
            transmit(lastPacket, pacing: false)
        }
        while !isFinished {
            guard let (data, from) = socket.receive(timeout: TimeInterval(timeoutSeconds)) else {
                if isFinished { return }
                timedOut()
                continue
            }
            guard from == peer, !isFinished else { continue }
            handle(data)
        }
    }

    private func handle(_ data: Data) {
        guard let opcode = TFTPPackets.opcode(of: data) else { return }
        switch opcode {
        case 3: handleData(data)
        case 4: handleAck(data)
        case 5: complete(.failed, message: TFTPPackets.errorMessage(data))
        default: break
        }
    }

    private func handleAck(_ data: Data) {
        guard let ack = TFTPPackets.block(of: data) else { return }
        if waitingForOptionAck && ack == 0 {
            waitingForOptionAck = false
            retries = 0
            _ = sendBlock(index: 0)
            return
        }
        guard ack == TFTPBlocks.number(forIndex: blockIndex) else { return }
        retries = 0
        if lastLength < blksize {
            complete(.completed, message: nil)
            return
        }
        blockIndex += 1
        _ = sendBlock(index: blockIndex)
    }

    private func handleData(_ data: Data) {
        guard direction == .upload, let block = TFTPPackets.block(of: data) else { return }
        let payload = TFTPPackets.payload(of: data)
        if payload.count > blksize {
            send(TFTPPackets.error(code: 4, message: "Illegal TFTP operation"))
            complete(.failed, message: "数据块超过协商大小")
            return
        }
        let expected = TFTPBlocks.number(forIndex: blockIndex)
        if block == expected {
            do {
                try writer?.write(contentsOf: payload)
            } catch {
                send(TFTPPackets.error(code: 3, message: "Disk full or allocation exceeded"))
                complete(.failed, message: "保存文件失败：\(error.localizedDescription)")
                return
            }
            fileSize = Int64(blockIndex) * Int64(blksize) + Int64(payload.count)
            retries = 0
            send(TFTPPackets.ack(block))
            publish(.inProgress)
            if payload.count < blksize {
                complete(.completed, message: nil)
            } else {
                blockIndex += 1
            }
            return
        }
        if blockIndex > 0 && block == TFTPBlocks.number(forIndex: blockIndex - 1) {
            transmit(lastPacket, pacing: false)
        }
    }

    @discardableResult
    private func sendBlock(index: Int) -> Bool {
        guard let length = TFTPBlocks.length(fileSize: fileSize, index: index, blksize: blksize) else {
            complete(.completed, message: nil)
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
                complete(.failed, message: "读取文件失败：文件在传输中被截断")
                return false
            }
            lastLength = payload.count
            blockIndex = index
            send(TFTPPackets.data(block: TFTPBlocks.number(forIndex: index), payload: payload), pacing: true)
            publish(.inProgress)
            return true
        } catch {
            complete(.failed, message: "读取文件失败：\(error.localizedDescription)")
            return false
        }
    }

    private func send(_ packet: Data, pacing: Bool = false) {
        lastPacket = packet
        transmit(packet, pacing: pacing)
    }

    private func transmit(_ packet: Data, pacing: Bool) {
        // Each transfer waits on its own queue, so a slow client cannot stall the listener.
        if pacing && frameGapMs > 0 {
            Thread.sleep(forTimeInterval: Double(frameGapMs) / 1000)
        }
        try? socket.send(packet, to: peer)
    }

    private func timedOut() {
        retries += 1
        if retries > maxRetries {
            complete(.failed, message: "等待客户端响应超时")
            return
        }
        transmit(lastPacket, pacing: false)
    }

    private var isFinished: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return finished
    }

    private func publish(_ status: TFTPTransferStatus) {
        let sent: Int64
        if direction == .download {
            sent = min(fileSize, Int64(blockIndex) * Int64(blksize) + Int64(lastLength == blksize && status == .inProgress ? 0 : lastLength))
        } else {
            sent = fileSize
        }
        onUpdate(item(status: status, bytes: max(0, sent), message: nil))
    }

    private func complete(_ status: TFTPTransferStatus, message: String?) {
        stateLock.lock()
        if finished {
            stateLock.unlock()
            return
        }
        finished = true
        stateLock.unlock()
        socket.close()
        try? reader?.close()
        try? writer?.close()
        reader = nil
        writer = nil
        if status == .completed, let partialURL {
            do {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: partialURL)
                } else {
                    try FileManager.default.moveItem(at: partialURL, to: fileURL)
                }
            } catch {
                try? FileManager.default.removeItem(at: partialURL)
                onFinish(item(status: .failed, bytes: fileSize, message: "保存文件失败：\(error.localizedDescription)"))
                return
            }
        } else if let partialURL {
            try? FileManager.default.removeItem(at: partialURL)
        }
        let bytes = status == .completed && direction == .download ? fileSize : fileSize
        onFinish(item(status: status, bytes: bytes, message: message))
    }

    private func item(status: TFTPTransferStatus, bytes: Int64, message: String?) -> TFTPTransferItem {
        let parts = key.split(separator: ":")
        let ip = parts.first.map(String.init) ?? key
        let port = UInt16(parts.last ?? "0") ?? 0
        return TFTPTransferItem(
            id: transferID,
            filename: filename,
            clientIP: ip,
            clientPort: port,
            direction: direction,
            bytesTransferred: bytes,
            totalBytes: direction == .download ? fileSize : (fileSize > 0 ? fileSize : nil),
            status: status,
            errorMessage: message,
            endTime: status == .inProgress ? nil : Date()
        )
    }
}
