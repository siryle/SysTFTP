import Foundation
import Network

public protocol SyslogServerDelegate: AnyObject {
    func syslogServerDidReceive(messages: [SyslogMessage])
    func syslogServerDidLog(_ text: String, isError: Bool)
    func syslogServerStatusChanged(isRunning: Bool, port: Int)
}

public final class SyslogServerService {
    public weak var delegate: SyslogServerDelegate?
    
    private var config: SyslogConfig
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.systftp.server.syslog", qos: .userInitiated)
    private let queueKey = DispatchSpecificKey<UInt8>()
    private var connections: [NWConnection] = []
    private var currentLogFileHandle: FileHandle?
    private var currentLogDateString: String = ""
    private var pendingMessages: [SyslogMessage] = []
    private var flushScheduled = false
    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    public init(config: SyslogConfig = SyslogConfig()) {
        self.config = config
        queue.setSpecific(key: queueKey, value: 1)
    }
    
    public func updateConfig(_ config: SyslogConfig) {
        self.config = config
    }
    
    public func start() throws {
        stop()
        
        // Ensure log directory exists if saving to file
        if config.saveToFile {
            try? FileManager.default.createDirectory(atPath: config.logDirectory, withIntermediateDirectories: true)
        }
        
        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true
        
        guard let port = NWEndpoint.Port(rawValue: UInt16(config.port)) else {
            throw NSError(domain: "SyslogServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "无效的 Syslog 端口：\(config.port)"])
        }
        
        let newListener = try NWListener(using: parameters, on: port)
        
        newListener.stateUpdateHandler = { [weak self, weak newListener] state in
            guard let self = self, let newListener = newListener, self.listener === newListener else { return }
            switch state {
            case .ready:
                self.delegate?.syslogServerDidLog("Syslog 服务正在监听 UDP 端口 \(self.config.port)", isError: false)
                self.delegate?.syslogServerStatusChanged(isRunning: true, port: self.config.port)
            case .failed(let error):
                self.delegate?.syslogServerDidLog("Syslog 服务错误：\(error.localizedDescription)（端口 \(self.config.port) 可能需要管理员权限）", isError: true)
                self.delegate?.syslogServerStatusChanged(isRunning: false, port: self.config.port)
            case .cancelled:
                self.delegate?.syslogServerStatusChanged(isRunning: false, port: self.config.port)
            default:
                break
            }
        }
        
        newListener.newConnectionHandler = { [weak self, weak newListener] connection in
            guard let self = self, let newListener = newListener, self.listener === newListener else {
                connection.cancel()
                return
            }
            self.handleIncomingConnection(connection)
        }
        
        self.listener = newListener
        newListener.start(queue: queue)
    }
    
    public func stop() {
        let wasRunning = listener != nil
        listener?.cancel()
        listener = nil
        onQueue {
            let open = self.connections
            self.connections.removeAll()
            open.forEach { $0.cancel() }
            self.flushPending()
        }
        try? currentLogFileHandle?.close()
        currentLogFileHandle = nil
        
        guard wasRunning else { return }
        delegate?.syslogServerDidLog("Syslog 服务已停止。", isError: false)
        delegate?.syslogServerStatusChanged(isRunning: false, port: config.port)
    }
    
    private func handleIncomingConnection(_ connection: NWConnection) {
        connections.append(connection)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, case .cancelled = state else { return }
            self.connections.removeAll { $0 === connection }
        }
        connection.start(queue: queue)
        receiveMessage(from: connection)
    }

    private func onQueue(_ work: () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            work()
        } else {
            queue.sync(execute: work)
        }
    }
    
    private func receiveMessage(from connection: NWConnection) {
        connection.receiveMessage { [weak self] content, context, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                if self.listener != nil {
                    self.delegate?.syslogServerDidLog("Syslog 接收错误：\(error.localizedDescription)", isError: true)
                }
                connection.cancel()
                return
            }
            
            if let data = content, !data.isEmpty {
                var clientIP = "未知"
                if case .hostPort(let host, _) = connection.endpoint {
                    clientIP = "\(host)"
                }
                self.processSyslogPacket(data: data, clientIP: clientIP)
            }
            // UDP sets isComplete for every datagram. That is not the end of the sender.
            guard self.listener != nil else {
                connection.cancel()
                return
            }
            self.receiveMessage(from: connection)
        }
    }
    
    private func processSyslogPacket(data: Data, clientIP: String) {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return
        }
        
        let message = parseSyslogMessage(raw: text, clientIP: clientIP)
        enqueue(message)
        
        if config.saveToFile {
            writeToFile(message: message)
        }
    }
    
    private func enqueue(_ message: SyslogMessage) {
        pendingMessages.append(message)
        guard !flushScheduled else { return }
        flushScheduled = true
        queue.asyncAfter(deadline: .now() + .milliseconds(50)) { [weak self] in
            self?.flushPending()
        }
    }

    private func flushPending() {
        flushScheduled = false
        let batch = pendingMessages
        pendingMessages.removeAll(keepingCapacity: true)
        guard !batch.isEmpty else { return }
        delegate?.syslogServerDidReceive(messages: batch)
    }

    // RFC 3164 / RFC 5424 Syslog Parser
    private func parseSyslogMessage(raw: String, clientIP: String) -> SyslogMessage {
        var pri = 13 // default: local7.notice (16 * 8 + 5 = 133 or user.notice 1 * 8 + 5 = 13)
        var remaining = raw
        
        // Extract <PRI>
        if remaining.hasPrefix("<") {
            if let closeIdx = remaining.firstIndex(of: ">") {
                let priStr = remaining[remaining.index(after: remaining.startIndex)..<closeIdx]
                if let p = Int(priStr) {
                    pri = p
                }
                remaining = String(remaining[remaining.index(after: closeIdx)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        
        let facilityInt = pri / 8
        let severityInt = pri % 8
        
        let facility = SyslogFacility(rawValue: min(23, max(0, facilityInt))) ?? .local7
        let severity = SyslogSeverity(rawValue: min(7, max(0, severityInt))) ?? .informational
        
        var hostname = clientIP
        var tag = ""
        var body = remaining
        
        // Try parsing timestamp and hostname in RFC 3164 format:
        // "Oct 21 14:32:00 myhost myapp[123]: packet dropped"
        let tokens = remaining.split(separator: " ", omittingEmptySubsequences: true)
        if tokens.count >= 4 {
            // Check if first 3 tokens look like "Oct 21 14:32:00"
            let monthToken = String(tokens[0])
            let months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
            if months.contains(monthToken) {
                hostname = String(tokens[3])
                let afterHost = tokens.dropFirst(4).joined(separator: " ")
                if let colonIdx = afterHost.firstIndex(of: ":") {
                    tag = String(afterHost[..<colonIdx])
                    body = String(afterHost[afterHost.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                } else {
                    body = afterHost
                }
            } else if let colonIdx = remaining.firstIndex(of: ":") {
                tag = String(remaining[..<colonIdx])
                body = String(remaining[remaining.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
            }
        } else if let colonIdx = remaining.firstIndex(of: ":") {
            tag = String(remaining[..<colonIdx])
            body = String(remaining[remaining.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
        }
        
        return SyslogMessage(
            timestamp: Date(),
            sourceIP: clientIP,
            facility: facility,
            severity: severity,
            hostname: hostname,
            tag: tag,
            message: body,
            raw: raw
        )
    }
    
    private func writeToFile(message: SyslogMessage) {
        let dateStr = dayFormatter.string(from: Date())
        
        // Daily rotation filename check (3CDaemon Hacker Option: Month-Day-Year.syslog.log)
        let filename = config.rotateDaily ? "\(dateStr).syslog.log" : "Syslog.log"
        let filePath = (config.logDirectory as NSString).appendingPathComponent(filename)
        
        if currentLogFileHandle == nil || currentLogDateString != dateStr {
            try? currentLogFileHandle?.close()
            currentLogDateString = dateStr
            
            if !FileManager.default.fileExists(atPath: filePath) {
                FileManager.default.createFile(atPath: filePath, contents: nil)
            }
            currentLogFileHandle = FileHandle(forWritingAtPath: filePath)
            currentLogFileHandle?.seekToEndOfFile()
        }
        
        let line = "\(message.formattedTimestamp) [\(message.sourceIP)] [\(message.facility.name)] [\(message.severity.name)] \(message.tag.isEmpty ? "" : "[\(message.tag)] ")\(message.message)\n"
        if let lineData = line.data(using: .utf8) {
            currentLogFileHandle?.write(lineData)
        }
    }
}
