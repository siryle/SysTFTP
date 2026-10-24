import Foundation
import Network

public protocol FTPServerDelegate: AnyObject {
    func ftpServerDidLog(_ message: String, isError: Bool)
    func ftpServerSessionUpdated(_ session: FTPSessionInfo)
    func ftpServerSessionEnded(sessionId: UUID)
    func ftpServerStatusChanged(isRunning: Bool, port: Int)
}

public final class FTPServerService {
    public weak var delegate: FTPServerDelegate?
    
    private var config: FTPServerConfig
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.systftp.server.ftp", qos: .userInitiated)
    
    private var activeSessions: [UUID: FTPClientSession] = [:]
    private let sessionLock = NSLock()
    
    public init(config: FTPServerConfig = FTPServerConfig()) {
        self.config = config
    }
    
    public func updateConfig(_ config: FTPServerConfig) {
        self.config = config
    }
    
    public func start() throws {
        stop()
        
        // Ensure default user directories exist
        for user in config.users {
            let url = URL(fileURLWithPath: user.userDirectory)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        guard let port = NWEndpoint.Port(rawValue: UInt16(config.port)) else {
            throw NSError(domain: "FTPServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "无效端口号：\(config.port)"])
        }
        
        let newListener = try NWListener(using: parameters, on: port)
        
        newListener.stateUpdateHandler = { [weak self, weak newListener] state in
            guard let self = self, let newListener = newListener, self.listener === newListener else { return }
            switch state {
            case .ready:
                self.delegate?.ftpServerDidLog("FTP 服务正在监听 TCP 端口 \(self.config.port)", isError: false)
                self.delegate?.ftpServerStatusChanged(isRunning: true, port: self.config.port)
            case .failed(let error):
                self.delegate?.ftpServerDidLog("FTP 服务启动失败：\(error.localizedDescription)（端口 \(self.config.port) 可能需要管理员权限）", isError: true)
                self.delegate?.ftpServerStatusChanged(isRunning: false, port: self.config.port)
            case .cancelled:
                self.delegate?.ftpServerStatusChanged(isRunning: false, port: self.config.port)
            default:
                break
            }
        }
        
        newListener.newConnectionHandler = { [weak self, weak newListener] connection in
            guard let self = self, let newListener = newListener, self.listener === newListener else {
                connection.cancel()
                return
            }
            self.handleNewClient(connection)
        }
        
        self.listener = newListener
        newListener.start(queue: queue)
    }
    
    public func stop() {
        let wasRunning = listener != nil
        listener?.cancel()
        listener = nil
        
        sessionLock.lock()
        let sessions = Array(activeSessions.values)
        activeSessions.removeAll()
        sessionLock.unlock()

        // Disconnect callbacks also acquire sessionLock.
        for session in sessions { session.disconnect() }
        
        guard wasRunning else { return }
        delegate?.ftpServerDidLog("FTP 服务已停止。", isError: false)
        delegate?.ftpServerStatusChanged(isRunning: false, port: config.port)
    }
    
    private func handleNewClient(_ connection: NWConnection) {
        var clientIP = "未知"
        var clientPort: UInt16 = 0
        if case .hostPort(let host, let port) = connection.endpoint {
            clientIP = "\(host)"
            clientPort = port.rawValue
        }
        
        let session = FTPClientSession(
            connection: connection,
            clientIP: clientIP,
            clientPort: clientPort,
            config: config,
            onLog: { [weak self] msg, isErr in
                self?.delegate?.ftpServerDidLog(msg, isError: isErr)
            },
            onSessionUpdate: { [weak self] info in
                self?.delegate?.ftpServerSessionUpdated(info)
            },
            onDisconnect: { [weak self] id in
                self?.sessionLock.lock()
                self?.activeSessions.removeValue(forKey: id)
                self?.sessionLock.unlock()
                self?.delegate?.ftpServerSessionEnded(sessionId: id)
            }
        )
        
        sessionLock.lock()
        activeSessions[session.id] = session
        sessionLock.unlock()
        
        session.start()
    }
}

// Inner handler for an individual FTP control connection
private final class FTPClientSession {
    let id = UUID()
    let connection: NWConnection
    let clientIP: String
    let clientPort: UInt16
    let config: FTPServerConfig
    let onLog: (String, Bool) -> Void
    let onSessionUpdate: (FTPSessionInfo) -> Void
    let onDisconnect: (UUID) -> Void
    
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let queue = DispatchQueue(label: "com.systftp.ftp.session", qos: .default)
    private var currentUser: FTPUser?
    private var pendingUsername: String?
    private var currentVirtualDir: String = "/"
    private var currentActualPath: String = ""
    private var renameFromPath: String?
    
    // Data connection settings
    private var isPassive = false
    private var passiveListener: NWListener?
    private var passiveDataConnection: NWConnection?
    private var activeDataEndpoint: (host: String, port: UInt16)?
    private var pasvGeneration = 0
    private var pasvAdvertised = false
    private var dataWaiter: ((NWConnection) -> Void)?
    private var didDisconnect = false
    
    private var lastActivityTime = Date()
    private var buffer = Data()
    
    init(connection: NWConnection, clientIP: String, clientPort: UInt16, config: FTPServerConfig, onLog: @escaping (String, Bool) -> Void, onSessionUpdate: @escaping (FTPSessionInfo) -> Void, onDisconnect: @escaping (UUID) -> Void) {
        self.connection = connection
        self.clientIP = clientIP
        self.clientPort = clientPort
        self.config = config
        self.onLog = onLog
        self.onSessionUpdate = onSessionUpdate
        self.onDisconnect = onDisconnect
        queue.setSpecific(key: queueKey, value: 1)
    }
    
    func start() {
        connection.start(queue: queue)
        sendReply(config.welcomeBanner)
        
        updateSessionInfo()
        onLog("FTP 客户端已连接：\(clientIP):\(clientPort)", false)
        
        startInactivityTimer()
        readCommand()
    }
    
    func disconnect() {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            finish()
        } else {
            queue.sync(execute: finish)
        }
    }

    private func finish() {
        if didDisconnect { return }
        didDisconnect = true
        passiveListener?.cancel()
        passiveDataConnection?.cancel()
        connection.cancel()
        onDisconnect(id)
    }
    
    private func startInactivityTimer() {
        queue.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, !self.didDisconnect else { return }
            if Date().timeIntervalSince(self.lastActivityTime) > Double(self.config.maxIdleTimeoutSeconds) {
                self.onLog("FTP 客户端 \(self.clientIP) 已断开：超过 \(self.config.maxIdleTimeoutSeconds) 秒无活动。", false)
                self.sendReply("421 Timeout - session closed due to inactivity.")
                self.finish()
                return
            }
            self.startInactivityTimer()
        }
    }
    
    private func readCommand() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] content, context, isComplete, error in
            guard let self = self else { return }
            if let data = content, !data.isEmpty {
                self.lastActivityTime = Date()
                self.buffer.append(data)
                if self.buffer.count > 64 * 1024 {
                    self.sendReply("500 Command line too long.")
                    self.disconnect()
                    return
                }
                self.processBuffer()
            }
            if self.didDisconnect { return }
            if let error = error {
                self.onLog("FTP 连接错误（\(self.clientIP)）：\(error.localizedDescription)", true)
                self.disconnect()
                return
            }
            if isComplete {
                self.disconnect()
                return
            }
            self.readCommand()
        }
    }
    
    private func processBuffer() {
        while let range = buffer.range(of: Data([0x0D, 0x0A])) ?? buffer.range(of: Data([0x0A])) {
            let cmdData = buffer.subdata(in: 0..<range.lowerBound)
            buffer.removeSubrange(0..<range.upperBound)
            if let line = String(data: cmdData, encoding: .utf8) ?? String(data: cmdData, encoding: .isoLatin1) {
                executeCommand(line.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }
    
    private func executeCommand(_ line: String) {
        guard !line.isEmpty else { return }
        
        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let verb = parts[0].uppercased()
        let arg = parts.count > 1 ? String(parts[1]) : ""
        
        // 3CDaemon Rev 10: Hide password in logs
        if verb == "PASS" && pendingUsername?.lowercased() != "anonymous" {
            onLog("FTP [\(clientIP)] > PASS ********", false)
        } else {
            onLog("FTP [\(clientIP)] > \(line)", false)
        }
        
        switch verb {
        case "USER":
            handleUSER(arg)
        case "PASS":
            handlePASS(arg)
        case "SYST":
            sendReply("215 UNIX Type: L8")
        case "FEAT":
            sendReply("211-Features:\r\n SIZE\r\n MDTM\r\n UTF8\r\n PASV\r\n211 End")
        case "PWD", "XPWD":
            sendReply("257 \"\(currentVirtualDir)\" is current directory.")
        case "TYPE":
            if arg.uppercased() == "I" || arg.uppercased() == "L 8" {
                sendReply("200 Type set to I (Binary).")
            } else {
                sendReply("504 Only binary mode is supported.")
            }
        case "PASV":
            handlePASV()
        case "PORT":
            handlePORT(arg)
        case "EPSV", "EPRT":
            // 3CDaemon Rev 9: Send 522 to indicate IPv6 extension unsupported, fall back to PASV/PORT
            sendReply("522 Extended commands not supported, use PASV or PORT instead.")
        case "CWD", "XCWD":
            handleCWD(arg)
        case "CDUP", "XCUP":
            handleCDUP()
        case "LIST", "NLST":
            handleLIST(isNlst: verb == "NLST", arg: arg)
        case "RETR":
            handleRETR(arg)
        case "STOR":
            handleSTOR(arg)
        case "DELE":
            handleDELE(arg)
        case "MKD", "XMKD":
            handleMKD(arg)
        case "RMD", "XRMD":
            handleRMD(arg)
        case "RNFR":
            handleRNFR(arg)
        case "RNTO":
            handleRNTO(arg)
        case "SIZE":
            handleSIZE(arg)
        case "NOOP":
            sendReply("200 OK")
        case "QUIT":
            sendReply("221 Goodbye.")
            disconnect()
        default:
            sendReply("502 Command not implemented.")
        }
    }
    
    private func handleUSER(_ name: String) {
        pendingUsername = name
        if name.lowercased() == "anonymous" {
            sendReply("331 Anonymous login allowed, please provide your email as password.")
        } else {
            sendReply("331 Password required for \(name).")
        }
    }
    
    private func handlePASS(_ pass: String) {
        guard let name = pendingUsername else {
            sendReply("503 Login with USER first.")
            return
        }
        
        guard let user = config.users.first(where: { $0.username.caseInsensitiveCompare(name) == .orderedSame }) else {
            sendReply("530 User '\(name)' not found.")
            return
        }
        
        guard user.canLogin else {
            sendReply("530 Access denied: User login is disabled.")
            return
        }
        
        guard user.verifyPassword(pass) else {
            sendReply("530 Invalid password.")
            return
        }
        
        currentUser = user
        currentVirtualDir = "/"
        currentActualPath = FTPPaths.resolve(root: user.userDirectory, currentVirtual: "/", requested: ".")?.actual ?? user.userDirectory
        try? FileManager.default.createDirectory(atPath: currentActualPath, withIntermediateDirectories: true)
        
        updateSessionInfo()
        onLog("FTP 用户 '\(user.username)' 登录成功。", false)
        sendReply("230 User \(user.username) logged in.")
    }
    
    private func handleCWD(_ path: String) {
        guard currentUser != nil else {
            sendReply("530 Please login with USER and PASS.")
            return
        }
        guard let resolved = resolvePath(path) else {
            sendReply("550 Access denied.")
            return
        }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: resolved.actual, isDirectory: &isDir), isDir.boolValue {
            currentVirtualDir = resolved.virtual
            currentActualPath = resolved.actual
            updateSessionInfo()
            sendReply("250 Directory successfully changed to \"\(currentVirtualDir)\".")
        } else {
            sendReply("550 Directory not found: \(path)")
        }
    }

    private func handleCDUP() {
        guard currentUser != nil else {
            sendReply("530 Please login.")
            return
        }
        if currentVirtualDir == "/" {
            sendReply("250 Already at root directory.")
            return
        }
        let parentVirtual = (currentVirtualDir as NSString).deletingLastPathComponent
        let target = parentVirtual.isEmpty ? "/" : parentVirtual
        guard let resolved = resolvePath(target) else {
            sendReply("550 Access denied.")
            return
        }
        currentVirtualDir = resolved.virtual
        currentActualPath = resolved.actual
        updateSessionInfo()
        sendReply("250 Directory changed to \"\(currentVirtualDir)\".")
    }

    private func handlePASV() {
        guard currentUser != nil else {
            sendReply("530 Please login.")
            return
        }
        passiveListener?.cancel()
        passiveListener = nil
        passiveDataConnection = nil
        pasvAdvertised = false
        pasvGeneration += 1
        let start = min(config.passivePortRangeStart, config.passivePortRangeEnd)
        let end = max(config.passivePortRangeStart, config.passivePortRangeEnd)
        bindPassivePort(port: start, end: end, generation: pasvGeneration)
    }

    private func bindPassivePort(port: Int, end: Int, generation: Int) {
        guard generation == pasvGeneration else { return }
        guard (1...65535).contains(port), port <= end, let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            sendReply("425 Can't open passive connection.")
            return
        }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        do {
            let listener = try NWListener(using: params, on: nwPort)
            listener.stateUpdateHandler = { [weak self] state in
                guard let self, generation == self.pasvGeneration else { return }
                switch state {
                case .ready:
                    guard !self.pasvAdvertised else { return }
                    self.pasvAdvertised = true
                    self.sendPassiveReady(port: UInt16(port))
                case .failed:
                    guard !self.pasvAdvertised else { return }
                    listener.cancel()
                    self.bindPassivePort(port: port + 1, end: end, generation: generation)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self, generation == self.pasvGeneration else {
                    connection.cancel()
                    return
                }
                connection.start(queue: self.queue)
                if let waiter = self.dataWaiter {
                    self.dataWaiter = nil
                    self.passiveListener?.cancel()
                    self.passiveListener = nil
                    self.passiveDataConnection = nil
                    waiter(connection)
                    return
                }
                if self.passiveDataConnection == nil {
                    self.passiveDataConnection = connection
                    return
                }
                connection.cancel()
            }
            passiveListener = listener
            isPassive = true
            listener.start(queue: queue)
        } catch {
            bindPassivePort(port: port + 1, end: end, generation: generation)
        }
    }

    private func sendPassiveReady(port: UInt16) {
        let octets = NetworkMonitorService.shared.currentPrimaryIP().split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else {
            sendReply("425 No reachable IPv4 address for passive mode.")
            return
        }
        let p1 = UInt8(port >> 8)
        let p2 = UInt8(port & 0xFF)
        sendReply("227 Entering Passive Mode (\(octets[0]),\(octets[1]),\(octets[2]),\(octets[3]),\(p1),\(p2))")
    }

    private func handlePORT(_ arg: String) {
        guard currentUser != nil else {
            sendReply("530 Please login.")
            return
        }
        guard let parsed = FTPPorts.parse(arg) else {
            sendReply("501 Syntax error in PORT parameters.")
            return
        }
        guard FTPPorts.allows(clientIP: connectedHost(), host: parsed.host) else {
            sendReply("504 PORT to a different host is not allowed.")
            return
        }
        activeDataEndpoint = parsed
        isPassive = false
        sendReply("200 PORT command successful.")
    }

    private func handleLIST(isNlst: Bool, arg: String) {
        guard currentUser != nil else {
            sendReply("530 Please login.")
            return
        }
        let targetDir: String
        if arg.isEmpty {
            targetDir = currentActualPath
        } else if let resolved = resolvePath(arg) {
            targetDir = resolved.actual
        } else {
            sendReply("550 Access denied.")
            return
        }
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: targetDir) else {
            sendReply("550 Cannot list directory.")
            return
        }

        var listing = ""
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM dd HH:mm"
        for item in items.sorted() {
            if isDisallowed(item) { continue }
            let fullPath = (targetDir as NSString).appendingPathComponent(item)
            let attrs = (try? FileManager.default.attributesOfItem(atPath: fullPath)) ?? [:]
            let isDirectory = (attrs[.type] as? FileAttributeType) == .typeDirectory
            let size = (attrs[.size] as? Int64) ?? 0
            let modDate = (attrs[.modificationDate] as? Date) ?? Date()
            if isNlst {
                listing += "\(item)\r\n"
            } else {
                let perm = isDirectory ? "drwxr-xr-x" : "-rw-r--r--"
                listing += "\(perm) 1 owner group \(size) \(formatter.string(from: modDate)) \(item)\r\n"
            }
        }
        openDataConnection { [weak self] dataConn in
            guard let self else { return }
            self.sendReply("150 Opening binary mode data connection for file list.")
            let data = listing.data(using: .utf8) ?? Data()
            dataConn.send(content: data, completion: .contentProcessed { [weak self] _ in
                dataConn.cancel()
                self?.sendReply("226 Transfer complete.")
            })
        }
    }

    private func handleRETR(_ filename: String) {
        guard let user = currentUser else {
            sendReply("530 Please login.")
            return
        }
        guard user.canDownload else {
            sendReply("550 Download permission denied.")
            return
        }
        guard let resolved = resolvePath(filename), !isDisallowed(filename), !isDisallowed(resolved.virtual) else {
            sendReply("550 Access denied: file is restricted.")
            return
        }
        let fileURL = URL(fileURLWithPath: resolved.actual)
        guard let reader = try? FileHandle(forReadingFrom: fileURL) else {
            sendReply("550 File not found or read error: \(filename)")
            return
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        openDataConnection { [weak self] dataConn in
            guard let self else { try? reader.close(); return }
            self.sendReply("150 Opening BINARY mode data connection for \(filename) (\(size) bytes).")
            func pump() {
                do {
                    let chunk = try reader.read(upToCount: 64 * 1024) ?? Data()
                    if chunk.isEmpty {
                        try? reader.close()
                        dataConn.cancel()
                        self.sendReply("226 Transfer complete.")
                        self.onLog("FTP 下载完成：\(filename)（\(size) 字节）", false)
                        return
                    }
                    dataConn.send(content: chunk, completion: .contentProcessed { error in
                        if error != nil {
                            try? reader.close()
                            dataConn.cancel()
                            self.sendReply("426 Connection closed; transfer aborted.")
                            return
                        }
                        pump()
                    })
                } catch {
                    try? reader.close()
                    dataConn.cancel()
                    self.sendReply("451 Read error: \(error.localizedDescription)")
                }
            }
            pump()
        }
    }

    private func handleSTOR(_ filename: String) {
        guard let user = currentUser else {
            sendReply("530 Please login.")
            return
        }
        guard user.canUpload else {
            sendReply("550 Upload permission denied.")
            return
        }
        guard let resolved = resolvePath(filename), !isDisallowed(filename), !isDisallowed(resolved.virtual), !isUserRoot(resolved.actual) else {
            sendReply("550 Access denied: file is restricted.")
            return
        }
        if FileManager.default.fileExists(atPath: resolved.actual) && !user.canOverwrite {
            sendReply("550 File already exists and overwrite permission is disabled.")
            return
        }
        let destination = URL(fileURLWithPath: resolved.actual)
        let partial = destination.appendingPathExtension("part")
        openDataConnection { [weak self] dataConn in
            guard let self else { return }
            FileManager.default.createFile(atPath: partial.path, contents: nil)
            guard let writer = try? FileHandle(forWritingTo: partial) else {
                self.sendReply("451 Cannot create upload file.")
                return
            }
            self.sendReply("150 Opening BINARY mode data connection for \(filename).")
            func receiveData() {
                dataConn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, isComplete, error in
                    if let content {
                        do { try writer.write(contentsOf: content) }
                        catch {
                            try? writer.close()
                            try? FileManager.default.removeItem(at: partial)
                            dataConn.cancel()
                            self.sendReply("451 Error saving uploaded file: \(error.localizedDescription)")
                            return
                        }
                    }
                    if error != nil {
                        try? writer.close()
                        try? FileManager.default.removeItem(at: partial)
                        dataConn.cancel()
                        self.sendReply("426 Connection closed; transfer aborted.")
                        return
                    }
                    if isComplete {
                        try? writer.close()
                        dataConn.cancel()
                        do {
                            if FileManager.default.fileExists(atPath: destination.path) {
                                _ = try FileManager.default.replaceItemAt(destination, withItemAt: partial)
                            } else {
                                try FileManager.default.moveItem(at: partial, to: destination)
                            }
                            let size = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
                            self.sendReply("226 Transfer complete (\(size) bytes).")
                            self.onLog("FTP 上传完成：\(filename)（\(size) 字节）", false)
                        } catch {
                            try? FileManager.default.removeItem(at: partial)
                            self.sendReply("451 Error saving uploaded file: \(error.localizedDescription)")
                        }
                        return
                    }
                    receiveData()
                }
            }
            receiveData()
        }
    }

    private func handleDELE(_ filename: String) {
        guard let user = currentUser else { sendReply("530 Please login."); return }
        guard user.canDelete else { sendReply("550 Delete permission denied."); return }
        guard let resolved = resolvePath(filename), !isDisallowed(resolved.virtual), !isUserRoot(resolved.actual) else {
            sendReply("550 Access denied.")
            return
        }
        do {
            try FileManager.default.removeItem(atPath: resolved.actual)
            sendReply("250 File deleted successfully.")
        } catch {
            sendReply("550 Delete failed: \(error.localizedDescription)")
        }
    }

    private func handleMKD(_ dir: String) {
        guard let user = currentUser else { sendReply("530 Please login."); return }
        guard user.canMkdir else { sendReply("550 Create directory permission denied."); return }
        guard let resolved = resolvePath(dir), !isUserRoot(resolved.actual) else {
            sendReply("550 Access denied.")
            return
        }
        do {
            try FileManager.default.createDirectory(atPath: resolved.actual, withIntermediateDirectories: true)
            sendReply("257 \"\(resolved.virtual)\" created.")
        } catch {
            sendReply("550 Create directory failed: \(error.localizedDescription)")
        }
    }

    private func handleRMD(_ dir: String) {
        guard let user = currentUser else { sendReply("530 Please login."); return }
        guard user.canRmdir else { sendReply("550 Remove directory permission denied."); return }
        guard let resolved = resolvePath(dir), !isDisallowed(resolved.virtual), !isUserRoot(resolved.actual) else {
            sendReply("550 Access denied.")
            return
        }
        do {
            try FileManager.default.removeItem(atPath: resolved.actual)
            sendReply("250 Directory removed.")
        } catch {
            sendReply("550 Remove directory failed: \(error.localizedDescription)")
        }
    }

    private func handleRNFR(_ filename: String) {
        guard let user = currentUser else { sendReply("530 Please login."); return }
        guard user.canRename else { sendReply("550 Rename permission denied."); return }
        guard let resolved = resolvePath(filename), !isUserRoot(resolved.actual) else {
            sendReply("550 Access denied.")
            return
        }
        renameFromPath = resolved.actual
        sendReply("350 Requested file action pending further information (RNTO).")
    }

    private func handleRNTO(_ filename: String) {
        guard let from = renameFromPath else {
            sendReply("503 Bad sequence of commands: RNFR required first.")
            return
        }
        guard let resolved = resolvePath(filename), !isDisallowed(resolved.virtual), !isUserRoot(resolved.actual) else {
            renameFromPath = nil
            sendReply("550 Access denied.")
            return
        }
        renameFromPath = nil
        do {
            try FileManager.default.moveItem(atPath: from, toPath: resolved.actual)
            sendReply("250 File renamed successfully.")
        } catch {
            sendReply("550 Rename failed: \(error.localizedDescription)")
        }
    }

    private func handleSIZE(_ filename: String) {
        guard currentUser != nil else { sendReply("530 Please login."); return }
        guard let resolved = resolvePath(filename), !isDisallowed(resolved.virtual) else {
            sendReply("550 Access denied.")
            return
        }
        let attrs = (try? FileManager.default.attributesOfItem(atPath: resolved.actual)) ?? [:]
        if let size = attrs[.size] as? Int64 {
            sendReply("213 \(size)")
        } else {
            sendReply("550 File not found.")
        }
    }

    private func isDisallowed(_ name: String) -> Bool {
        let n = name.lowercased()
        for d in config.disallowedFiles {
            if n == d.lowercased() || n.contains(d.lowercased()) {
                return true
            }
        }
        return false
    }
    
    private func resolvePath(_ path: String) -> (virtual: String, actual: String)? {
        guard let user = currentUser else { return nil }
        return FTPPaths.resolve(root: user.userDirectory, currentVirtual: currentVirtualDir, requested: path)
    }

    private func isUserRoot(_ path: String) -> Bool {
        guard let user = currentUser else { return false }
        let root = FTPPaths.resolve(root: user.userDirectory, currentVirtual: "/", requested: ".")?.actual ?? user.userDirectory
        return URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path == root
    }
    
    private func openDataConnection(completion: @escaping (NWConnection) -> Void) {
        if isPassive {
            if let connection = passiveDataConnection {
                passiveDataConnection = nil
                passiveListener?.cancel()
                passiveListener = nil
                completion(connection)
                return
            }
            let generation = pasvGeneration
            dataWaiter = completion
            queue.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self, self.pasvGeneration == generation, self.dataWaiter != nil else { return }
                self.dataWaiter = nil
                self.pasvGeneration += 1
                self.passiveListener?.cancel()
                self.passiveListener = nil
                self.passiveDataConnection?.cancel()
                self.passiveDataConnection = nil
                self.sendReply("425 Can't open data connection.")
            }
            return
        }
        guard let endpoint = activeDataEndpoint, FTPPorts.allows(clientIP: connectedHost(), host: endpoint.host), let port = NWEndpoint.Port(rawValue: endpoint.port) else {
            sendReply("425 Use PASV or PORT first.")
            return
        }
        let connection = NWConnection(host: NWEndpoint.Host(endpoint.host), port: port, using: .tcp)
        var finished = false
        connection.stateUpdateHandler = { [weak self] state in
            guard !finished else { return }
            switch state {
            case .ready:
                finished = true
                completion(connection)
            case .failed, .cancelled:
                finished = true
                self?.sendReply("425 Can't open data connection.")
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard !finished else { return }
            finished = true
            connection.cancel()
            self?.sendReply("425 Can't open data connection.")
        }
    }

    private func connectedHost() -> String {
        if case .hostPort(let host, _) = connection.endpoint {
            return "\(host)"
        }
        return clientIP
    }

    private func sendReply(_ reply: String) {
        let formatted = reply.hasSuffix("\r\n") ? reply : reply + "\r\n"
        if let data = formatted.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed({ _ in }))
        }
    }
    
    private func updateSessionInfo() {
        let info = FTPSessionInfo(
            id: id,
            clientIP: clientIP,
            clientPort: clientPort,
            username: currentUser?.username ?? pendingUsername ?? "未登录",
            currentDirectory: currentVirtualDir,
            isConnected: true
        )
        onSessionUpdate(info)
    }
}
