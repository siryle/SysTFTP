import Foundation
import Network

public protocol TFTPServerDelegate: AnyObject {
    func tftpServerDidLog(_ message: String, isError: Bool)
    func tftpServerTransferUpdated(_ item: TFTPTransferItem)
    func tftpServerStatusChanged(isRunning: Bool, port: Int)
}

public final class TFTPServerService {
    public weak var delegate: TFTPServerDelegate?
    
    private var config: TFTPServerConfig
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.systftp.server.tftp", qos: .userInitiated)
    
    // Active transfers map: "clientIP:clientPort" -> TransferSession
    private var activeSessions: [String: TFTPSession] = [:]
    private let sessionLock = NSLock()
    
    public init(config: TFTPServerConfig = TFTPServerConfig()) {
        self.config = config
    }
    
    public func updateConfig(_ config: TFTPServerConfig) {
        self.config = config
    }
    
    public func start() throws {
        stop()
        
        // Ensure root directory exists
        let rootURL = URL(fileURLWithPath: config.rootDirectory)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        
        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true
        
        guard let port = NWEndpoint.Port(rawValue: UInt16(config.port)) else {
            throw NSError(domain: "TFTPServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "无效端口号：\(config.port)"])
        }
        
        let newListener = try NWListener(using: parameters, on: port)
        
        newListener.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.delegate?.tftpServerDidLog("TFTP 服务正在监听 UDP 端口 \(self.config.port)，根目录：\(self.config.rootDirectory)", isError: false)
                self.delegate?.tftpServerStatusChanged(isRunning: true, port: self.config.port)
            case .failed(let error):
                self.delegate?.tftpServerDidLog("TFTP 服务启动失败：\(error.localizedDescription)（端口 \(self.config.port) 可能需要管理员权限或已被占用）", isError: true)
                self.delegate?.tftpServerStatusChanged(isRunning: false, port: self.config.port)
            case .cancelled:
                self.delegate?.tftpServerStatusChanged(isRunning: false, port: self.config.port)
            default:
                break
            }
        }
        
        newListener.newConnectionHandler = { [weak self] connection in
            self?.handleIncomingConnection(connection)
        }
        
        self.listener = newListener
        newListener.start(queue: queue)
    }
    
    public func stop() {
        listener?.cancel()
        listener = nil
        
        sessionLock.lock()
        for session in activeSessions.values {
            session.cancel()
        }
        activeSessions.removeAll()
        sessionLock.unlock()
        
        delegate?.tftpServerDidLog("TFTP 服务已停止。", isError: false)
        delegate?.tftpServerStatusChanged(isRunning: false, port: config.port)
    }
    
    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receivePacket(on: connection)
    }
    
    private func receivePacket(on connection: NWConnection) {
        connection.receiveMessage { [weak self] content, context, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                self.delegate?.tftpServerDidLog("TFTP 接收错误：\(error.localizedDescription)", isError: true)
                connection.cancel()
                return
            }
            
            guard let data = content, !data.isEmpty else {
                return
            }
            
            self.processPacket(data: data, connection: connection)
        }
    }
    
    private func processPacket(data: Data, connection: NWConnection) {
        guard data.count >= 2 else { return }
        let opcode = UInt16(data[0]) << 8 | UInt16(data[1])
        
        var clientIP = "未知"
        var clientPort: UInt16 = 0
        if case .hostPort(let host, let port) = connection.endpoint {
            clientIP = "\(host)"
            clientPort = port.rawValue
        }
        let sessionKey = "\(clientIP):\(clientPort)"
        
        switch opcode {
        case 1: // RRQ (Read Request / Download)
            handleRRQ(data: data.subdata(in: 2..<data.count), clientIP: clientIP, clientPort: clientPort, connection: connection, sessionKey: sessionKey)
        case 2: // WRQ (Write Request / Upload)
            handleWRQ(data: data.subdata(in: 2..<data.count), clientIP: clientIP, clientPort: clientPort, connection: connection, sessionKey: sessionKey)
        case 3: // DATA (Write upload incoming data)
            sessionLock.lock()
            let session = activeSessions[sessionKey]
            sessionLock.unlock()
            session?.handleDataPacket(data: data)
        case 4: // ACK (Read download ack from client)
            sessionLock.lock()
            let session = activeSessions[sessionKey]
            sessionLock.unlock()
            session?.handleAckPacket(data: data)
        case 5: // ERROR
            let errorMsg = parseErrorMessage(data: data)
            delegate?.tftpServerDidLog("收到来自 \(sessionKey) 的 TFTP 错误：\(errorMsg)", isError: true)
            sessionLock.lock()
            activeSessions.removeValue(forKey: sessionKey)?.cancel()
            sessionLock.unlock()
        default:
            sendError(connection: connection, code: 4, message: "Illegal TFTP operation")
        }
    }
    
    private func handleRRQ(data: Data, clientIP: String, clientPort: UInt16, connection: NWConnection, sessionKey: String) {
        let (filename, mode, options) = parseRequest(data: data)
        delegate?.tftpServerDidLog("TFTP 下载请求（RRQ）：'\(filename)'，客户端 \(clientIP):\(clientPort)，模式=\(mode)，选项=\(options)", isError: false)
        
        let safePath = resolveSafePath(filename: filename)
        guard let fileURL = safePath, FileManager.default.fileExists(atPath: fileURL.path) else {
            sendError(connection: connection, code: 1, message: "File not found: \(filename)")
            delegate?.tftpServerDidLog("TFTP 文件不存在：\(filename)", isError: true)
            return
        }
        
        guard let fileData = try? Data(contentsOf: fileURL) else {
            sendError(connection: connection, code: 2, message: "Access violation reading file")
            return
        }
        
        let transferItem = TFTPTransferItem(
            filename: filename,
            clientIP: clientIP,
            clientPort: clientPort,
            direction: .download,
            bytesTransferred: 0,
            totalBytes: Int64(fileData.count),
            status: .inProgress
        )
        self.delegate?.tftpServerTransferUpdated(transferItem)
        
        let session = TFTPSession(
            sessionKey: sessionKey,
            filename: filename,
            clientIP: clientIP,
            clientPort: clientPort,
            direction: .download,
            fileData: fileData,
            fileURL: fileURL,
            options: options,
            config: config,
            connection: connection,
            onUpdate: { [weak self] updatedItem in
                self?.delegate?.tftpServerTransferUpdated(updatedItem)
            },
            onFinish: { [weak self] item in
                self?.sessionLock.lock()
                self?.activeSessions.removeValue(forKey: sessionKey)
                self?.sessionLock.unlock()
                self?.delegate?.tftpServerTransferUpdated(item)
                self?.delegate?.tftpServerDidLog("TFTP 下载完成：\(item.filename) → \(item.clientIP)（\(item.bytesTransferred) 字节）", isError: false)
            }
        )
        
        sessionLock.lock()
        activeSessions[sessionKey] = session
        sessionLock.unlock()
        
        session.startReadTransfer()
    }
    
    private func handleWRQ(data: Data, clientIP: String, clientPort: UInt16, connection: NWConnection, sessionKey: String) {
        let (filename, mode, options) = parseRequest(data: data)
        delegate?.tftpServerDidLog("TFTP 上传请求（WRQ）：'\(filename)'，客户端 \(clientIP):\(clientPort)，模式=\(mode)，选项=\(options)", isError: false)
        
        guard let fileURL = resolveSafePath(filename: filename) else {
            sendError(connection: connection, code: 2, message: "Access violation / Invalid filename path")
            return
        }
        
        if FileManager.default.fileExists(atPath: fileURL.path) && !config.allowOverwrite {
            sendError(connection: connection, code: 6, message: "File already exists and overwrite is disabled")
            delegate?.tftpServerDidLog("TFTP 已阻止覆盖文件：\(filename)", isError: true)
            return
        }
        
        if config.allowCreateDir {
            let parentDir = fileURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        
        let expectedSize = options["tsize"].flatMap { Int64($0) }
        
        let session = TFTPSession(
            sessionKey: sessionKey,
            filename: filename,
            clientIP: clientIP,
            clientPort: clientPort,
            direction: .upload,
            fileData: Data(),
            fileURL: fileURL,
            options: options,
            config: config,
            connection: connection,
            onUpdate: { [weak self] updatedItem in
                self?.delegate?.tftpServerTransferUpdated(updatedItem)
            },
            onFinish: { [weak self] item in
                self?.sessionLock.lock()
                self?.activeSessions.removeValue(forKey: sessionKey)
                self?.sessionLock.unlock()
                self?.delegate?.tftpServerTransferUpdated(item)
                self?.delegate?.tftpServerDidLog("TFTP 上传完成：\(item.filename) ← \(item.clientIP)（\(item.bytesTransferred) 字节）", isError: false)
            }
        )
        
        sessionLock.lock()
        activeSessions[sessionKey] = session
        sessionLock.unlock()
        
        session.startWriteTransfer(expectedSize: expectedSize)
    }
    
    private func resolveSafePath(filename: String) -> URL? {
        let rootURL = URL(fileURLWithPath: config.rootDirectory).standardized
        let cleanName = filename.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !cleanName.contains("..") else { return nil }
        
        // Security: Block 3CDaemon config overwrite attempts as specified in Rev 7
        let lower = cleanName.lowercased()
        if lower == "3cdaemon.ini" || lower == "profiles.ftp" || lower == "noaccess.ftp" || lower.hasSuffix(".plist") {
            return nil
        }
        
        let targetURL = rootURL.appendingPathComponent(cleanName).standardized
        if targetURL.path.hasPrefix(rootURL.path) {
            return targetURL
        }
        return nil
    }
    
    private func parseRequest(data: Data) -> (filename: String, mode: String, options: [String: String]) {
        var strings: [String] = []
        var current = Data()
        for byte in data {
            if byte == 0 {
                if let str = String(data: current, encoding: .utf8) ?? String(data: current, encoding: .isoLatin1) {
                    strings.append(str)
                }
                current.removeAll()
            } else {
                current.append(byte)
            }
        }
        
        let filename = strings.indices.contains(0) ? strings[0] : ""
        let mode = strings.indices.contains(1) ? strings[1].lowercased() : "octet"
        
        var options: [String: String] = [:]
        var i = 2
        while i + 1 < strings.count {
            let key = strings[i].lowercased()
            let val = strings[i+1]
            options[key] = val
            i += 2
        }
        
        return (filename, mode, options)
    }
    
    private func parseErrorMessage(data: Data) -> String {
        guard data.count > 4 else { return "未知错误" }
        let msgData = data.subdata(in: 4..<data.count)
        return String(data: msgData, encoding: .utf8) ?? "TFTP 错误代码 \(data[2])\(data[3])"
    }
    
    private func sendError(connection: NWConnection, code: UInt16, message: String) {
        var packet = Data([0x00, 0x05, UInt8(code >> 8), UInt8(code & 0xFF)])
        if let msgData = message.data(using: .utf8) {
            packet.append(msgData)
        }
        packet.append(0x00)
        connection.send(content: packet, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
}

// Inner helper class managing a single TFTP transfer session
private final class TFTPSession {
    let sessionKey: String
    let filename: String
    let clientIP: String
    let clientPort: UInt16
    let direction: TFTPTransferDirection
    var fileData: Data
    let fileURL: URL
    let options: [String: String]
    let config: TFTPServerConfig
    let connection: NWConnection
    let onUpdate: (TFTPTransferItem) -> Void
    let onFinish: (TFTPTransferItem) -> Void
    
    var blksize: Int = 512
    var timeoutSeconds: Int = 5
    var currentBlock: UInt16 = 0
    var isCancelled: Bool = false
    var lastActivityTime: Date = Date()
    var bytesTransferred: Int64 = 0
    var totalBytes: Int64?
    
    init(sessionKey: String, filename: String, clientIP: String, clientPort: UInt16, direction: TFTPTransferDirection, fileData: Data, fileURL: URL, options: [String: String], config: TFTPServerConfig, connection: NWConnection, onUpdate: @escaping (TFTPTransferItem) -> Void, onFinish: @escaping (TFTPTransferItem) -> Void) {
        self.sessionKey = sessionKey
        self.filename = filename
        self.clientIP = clientIP
        self.clientPort = clientPort
        self.direction = direction
        self.fileData = fileData
        self.fileURL = fileURL
        self.options = options
        self.config = config
        self.connection = connection
        self.onUpdate = onUpdate
        self.onFinish = onFinish
        
        if let optBlk = options["blksize"], let b = Int(optBlk), b >= 8 && b <= 65464 {
            self.blksize = b
        }
        if let optTimeout = options["timeout"], let t = Int(optTimeout), t >= 1 && t <= 255 {
            self.timeoutSeconds = t
        }
    }
    
    func cancel() {
        isCancelled = true
        connection.cancel()
    }
    
    func startReadTransfer() {
        totalBytes = Int64(fileData.count)
        
        // Check if options negotiation is requested
        if !options.isEmpty {
            sendOACK(isRead: true)
        } else {
            currentBlock = 1
            sendNextDataBlock()
        }
    }
    
    func startWriteTransfer(expectedSize: Int64?) {
        totalBytes = expectedSize
        if !options.isEmpty {
            sendOACK(isRead: false)
        } else {
            sendAck(blockNum: 0)
        }
    }
    
    private func sendOACK(isRead: Bool) {
        var oack = Data([0x00, 0x06]) // Opcode 6
        if options["blksize"] != nil {
            appendOption(to: &oack, name: "blksize", value: "\(blksize)")
        }
        if options["timeout"] != nil {
            appendOption(to: &oack, name: "timeout", value: "\(timeoutSeconds)")
        }
        if options["tsize"] != nil {
            let size = isRead ? fileData.count : 0
            appendOption(to: &oack, name: "tsize", value: "\(size)")
        }
        
        connection.send(content: oack, completion: .contentProcessed { [weak self] error in
            if error != nil {
                self?.fail(message: "发送 OACK 失败")
            }
        })
    }
    
    private func appendOption(to data: inout Data, name: String, value: String) {
        if let n = name.data(using: .utf8), let v = value.data(using: .utf8) {
            data.append(n)
            data.append(0x00)
            data.append(v)
            data.append(0x00)
        }
    }
    
    func handleAckPacket(data: Data) {
        guard data.count >= 4 else { return }
        let ackBlock = UInt16(data[2]) << 8 | UInt16(data[3])
        
        if ackBlock == 0 && currentBlock == 0 {
            // OACK acknowledged! Send block 1
            currentBlock = 1
            sendNextDataBlock()
            return
        }
        
        if ackBlock == currentBlock {
            bytesTransferred = min(Int64(fileData.count), Int64(currentBlock) * Int64(blksize))
            updateProgress()
            
            // Check if transfer finished
            let offset = Int(currentBlock - 1) * blksize
            if offset + blksize >= fileData.count {
                // Done!
                finishSuccess()
                return
            }
            
            // Increment block with 16-bit rollover support
            currentBlock = (currentBlock == 65535) ? 0 : (currentBlock + 1)
            sendNextDataBlock()
        }
    }
    
    func handleDataPacket(data: Data) {
        guard data.count >= 4 else { return }
        let blockNum = UInt16(data[2]) << 8 | UInt16(data[3])
        let payload = data.subdata(in: 4..<data.count)
        
        let expectedBlock = (currentBlock == 65535) ? 0 : (currentBlock + 1)
        if blockNum == expectedBlock {
            currentBlock = blockNum
            fileData.append(payload)
            bytesTransferred += Int64(payload.count)
            updateProgress()
            
            sendAck(blockNum: currentBlock)
            
            // If payload < blksize, transfer is complete
            if payload.count < blksize {
                do {
                    try fileData.write(to: fileURL)
                    finishSuccess()
                } catch {
                    fail(message: "保存文件失败：\(error.localizedDescription)")
                }
            }
        } else if blockNum == currentBlock {
            // Duplicate packet, re-ack
            sendAck(blockNum: currentBlock)
        }
    }
    
    private func sendNextDataBlock() {
        guard !isCancelled else { return }
        let offset = Int(currentBlock - 1) * blksize
        guard offset < fileData.count else { return }
        let end = min(offset + blksize, fileData.count)
        let chunk = fileData.subdata(in: offset..<end)
        
        var packet = Data([0x00, 0x03, UInt8(currentBlock >> 8), UInt8(currentBlock & 0xFF)])
        packet.append(chunk)
        
        if config.frameGapMs > 0 {
            Thread.sleep(forTimeInterval: Double(config.frameGapMs) / 1000.0)
        }
        
        connection.send(content: packet, completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.fail(message: "发送 DATA 失败：\(error.localizedDescription)")
            }
        })
    }
    
    private func sendAck(blockNum: UInt16) {
        let ack = Data([0x00, 0x04, UInt8(blockNum >> 8), UInt8(blockNum & 0xFF)])
        connection.send(content: ack, completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.fail(message: "发送 ACK 失败：\(error.localizedDescription)")
            }
        })
    }
    
    private func updateProgress() {
        let item = TFTPTransferItem(
            filename: filename,
            clientIP: clientIP,
            clientPort: clientPort,
            direction: direction,
            bytesTransferred: bytesTransferred,
            totalBytes: totalBytes,
            status: .inProgress
        )
        onUpdate(item)
    }
    
    private func finishSuccess() {
        let item = TFTPTransferItem(
            filename: filename,
            clientIP: clientIP,
            clientPort: clientPort,
            direction: direction,
            bytesTransferred: bytesTransferred,
            totalBytes: totalBytes ?? bytesTransferred,
            status: .completed,
            endTime: Date()
        )
        onFinish(item)
        connection.cancel()
    }
    
    private func fail(message: String) {
        let item = TFTPTransferItem(
            filename: filename,
            clientIP: clientIP,
            clientPort: clientPort,
            direction: direction,
            bytesTransferred: bytesTransferred,
            totalBytes: totalBytes,
            status: .failed,
            errorMessage: message,
            endTime: Date()
        )
        onFinish(item)
        connection.cancel()
    }
}
