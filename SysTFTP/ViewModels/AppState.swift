import Foundation
import SwiftUI
import Combine

public enum AppNavigationItem: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case tftpServer = "TFTP Server"
    case tftpClient = "TFTP Client"
    case ftpServer = "FTP Server"
    case syslogServer = "Syslog Server"
    case settings = "Settings"
    
    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .overview: return "概览"
        case .tftpServer: return "TFTP 服务器"
        case .tftpClient: return "TFTP 客户端"
        case .ftpServer: return "FTP 服务器"
        case .syslogServer: return "Syslog 日志服务器"
        case .settings: return "设置"
        }
    }
    
    public var icon: String {
        switch self {
        case .overview: return "square.grid.2x2.fill"
        case .tftpServer: return "server.rack"
        case .tftpClient: return "arrow.up.arrow.down.circle"
        case .ftpServer: return "externaldrive.connected.to.line.below"
        case .syslogServer: return "waveform.path.ecg.rectangle"
        case .settings: return "gearshape"
        }
    }
}

@MainActor
public final class AppState: ObservableObject {
    public static let shared = AppState()
    
    // Navigation selection
    @Published public var selectedItem: AppNavigationItem = .overview
    
    // Service state flags
    @Published public var isTFTPServerRunning: Bool = false
    @Published public var isFTPServerRunning: Bool = false
    @Published public var isSyslogServerRunning: Bool = false
    
    // Configurations
    @Published public var tftpServerConfig = TFTPServerConfig() {
        didSet {
            if oldValue.port != tftpServerConfig.port { defaults.set(tftpServerConfig.port, forKey: "ports.tftp") }
        }
    }
    @Published public var tftpClientConfig = TFTPClientConfig()
    @Published public var ftpServerConfig = FTPServerConfig() {
        didSet {
            if oldValue.port != ftpServerConfig.port { defaults.set(ftpServerConfig.port, forKey: "ports.ftp") }
        }
    }
    @Published public var syslogConfig = SyslogConfig() {
        didSet {
            if oldValue.port != syslogConfig.port { defaults.set(syslogConfig.port, forKey: "ports.syslog") }
        }
    }
    
    // Data collections
    @Published public var tftpTransfers: [TFTPTransferItem] = []
    @Published public var ftpSessions: [FTPSessionInfo] = []
    @Published public var syslogMessages: [SyslogMessage] = []
    
    // Real-time console logs
    @Published public var tftpLogs: [String] = []
    @Published public var ftpLogs: [String] = []
    @Published public var tftpClientLogs: [String] = []
    @Published public var generalLogs: [String] = []
    
    // Client transfer state
    @Published public var isClientTransferring: Bool = false
    @Published public var clientTransferProgress: Double = 0.0
    @Published public var clientTransferredBytes: Int64 = 0
    @Published public var clientTotalBytes: Int64? = nil
    @Published public var clientSpeedString: String = "0 KB/s"
    @Published public var clientStatusMessage: String = "就绪"
    
    // Background Services
    public let tftpServerService = TFTPServerService()
    public let tftpClientService = TFTPClientService()
    public let ftpServerService = FTPServerService()
    public let syslogServerService = SyslogServerService()
    public let networkMonitor = NetworkMonitorService.shared
    public let portForwarding = PortForwardingService()
    
    private let defaults: UserDefaults
    private let maxLogCount = 1000
    private let maxSyslogCount = 2000
    
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        setupDelegates()
        loadConfigs()
    }

    public var hasRunningServices: Bool {
        isTFTPServerRunning || isFTPServerRunning || isSyslogServerRunning
    }

    public var currentPortPreset: ServerPortPreset? {
        ServerPortPreset.allCases.first {
            $0.matches(tftp: tftpServerConfig.port, ftp: ftpServerConfig.port, syslog: syslogConfig.port)
        }
    }

    @discardableResult
    public func applyPortPreset(_ preset: ServerPortPreset) -> Bool {
        guard !hasRunningServices else { return false }
        tftpServerConfig.port = preset.ports[0]
        ftpServerConfig.port = preset.ports[1]
        syslogConfig.port = preset.ports[2]
        appendGeneralLog("已应用\(preset.title)：\(preset.summary)")
        return true
    }
    
    private func setupDelegates() {
        tftpServerService.delegate = self
        tftpClientService.delegate = self
        ftpServerService.delegate = self
        syslogServerService.delegate = self
    }
    
    // MARK: - TFTP Server Actions
    public func toggleTFTPServer() {
        if isTFTPServerRunning {
            tftpServerService.stop()
        } else {
            tftpServerService.updateConfig(tftpServerConfig)
            do {
                try tftpServerService.start()
            } catch {
                appendTFTPLog("TFTP 服务启动失败：\(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - FTP Server Actions
    public func toggleFTPServer() {
        if isFTPServerRunning {
            ftpServerService.stop()
        } else {
            ftpServerService.updateConfig(ftpServerConfig)
            do {
                try ftpServerService.start()
            } catch {
                appendFTPLog("FTP 服务启动失败：\(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Syslog Server Actions
    public func toggleSyslogServer() {
        if isSyslogServerRunning {
            syslogServerService.stop()
        } else {
            syslogServerService.updateConfig(syslogConfig)
            do {
                try syslogServerService.start()
            } catch {
                appendGeneralLog("Syslog 服务启动失败：\(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Master Toggle
    public func startAllServices() {
        if !isTFTPServerRunning { toggleTFTPServer() }
        if !isFTPServerRunning { toggleFTPServer() }
        if !isSyslogServerRunning { toggleSyslogServer() }
    }
    
    public func stopAllServices() {
        if isTFTPServerRunning { toggleTFTPServer() }
        if isFTPServerRunning { toggleFTPServer() }
        if isSyslogServerRunning { toggleSyslogServer() }
        isTFTPServerRunning = false
        isFTPServerRunning = false
        isSyslogServerRunning = false
    }
    
    // MARK: - TFTP Client Actions
    public func startClientTransfer() {
        isClientTransferring = true
        clientTransferProgress = 0.0
        clientTransferredBytes = 0
        clientStatusMessage = "正在连接…"
        tftpClientService.startTransfer(config: tftpClientConfig)
    }
    
    public func cancelClientTransfer() {
        tftpClientService.cancel()
        isClientTransferring = false
        clientStatusMessage = "已取消"
    }
    
    // MARK: - Log Helpers
    public func appendTFTPLog(_ text: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        tftpLogs.append("[\(timestamp)] \(text)")
        if tftpLogs.count > maxLogCount { tftpLogs.removeFirst() }
    }
    
    public func appendFTPLog(_ text: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        ftpLogs.append("[\(timestamp)] \(text)")
        if ftpLogs.count > maxLogCount { ftpLogs.removeFirst() }
    }
    
    public func appendClientLog(_ text: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        tftpClientLogs.append("[\(timestamp)] \(text)")
        if tftpClientLogs.count > maxLogCount { tftpClientLogs.removeFirst() }
    }
    
    public func appendGeneralLog(_ text: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        generalLogs.append("[\(timestamp)] \(text)")
        if generalLogs.count > maxLogCount { generalLogs.removeFirst() }
    }
    
    public func clearSyslogs() {
        syslogMessages.removeAll()
    }
    
    private func loadConfigs() {
        let tftp = defaults.integer(forKey: "ports.tftp")
        let ftp = defaults.integer(forKey: "ports.ftp")
        let syslog = defaults.integer(forKey: "ports.syslog")
        if (1...65535).contains(tftp) { tftpServerConfig.port = tftp }
        if (1...65535).contains(ftp) { ftpServerConfig.port = ftp }
        if (1...65535).contains(syslog) { syslogConfig.port = syslog }
    }
}

// MARK: - Delegates Conformance
extension AppState: TFTPServerDelegate {
    public nonisolated func tftpServerDidLog(_ message: String, isError: Bool) {
        Task { @MainActor in
            self.appendTFTPLog(message)
        }
    }
    
    public nonisolated func tftpServerTransferUpdated(_ item: TFTPTransferItem) {
        Task { @MainActor in
            if let idx = self.tftpTransfers.firstIndex(where: { $0.id == item.id || ($0.filename == item.filename && $0.clientIP == item.clientIP && $0.clientPort == item.clientPort) }) {
                self.tftpTransfers[idx] = item
            } else {
                self.tftpTransfers.insert(item, at: 0)
            }
        }
    }
    
    public nonisolated func tftpServerStatusChanged(isRunning: Bool, port: Int) {
        Task { @MainActor in
            self.isTFTPServerRunning = isRunning
            self.tftpServerConfig.isRunning = isRunning
        }
    }
}

extension AppState: TFTPClientDelegate {
    public nonisolated func tftpClientDidLog(_ message: String, isError: Bool) {
        Task { @MainActor in
            self.appendClientLog(message)
        }
    }
    
    public nonisolated func tftpClientProgressUpdated(bytesTransferred: Int64, totalBytes: Int64?, speedBytesPerSec: Double, progress: Double) {
        Task { @MainActor in
            self.clientTransferredBytes = bytesTransferred
            self.clientTotalBytes = totalBytes
            self.clientTransferProgress = progress
            
            if speedBytesPerSec > 1024 * 1024 {
                self.clientSpeedString = String(format: "%.2f MB/s", speedBytesPerSec / (1024 * 1024))
            } else {
                self.clientSpeedString = String(format: "%.1f KB/s", speedBytesPerSec / 1024)
            }
            self.clientStatusMessage = "正在传输：\(self.clientSpeedString)"
        }
    }
    
    public nonisolated func tftpClientDidComplete(success: Bool, message: String) {
        Task { @MainActor in
            self.isClientTransferring = false
            self.clientStatusMessage = message
            self.appendClientLog(message)
        }
    }
}

extension AppState: FTPServerDelegate {
    public nonisolated func ftpServerDidLog(_ message: String, isError: Bool) {
        Task { @MainActor in
            self.appendFTPLog(message)
        }
    }
    
    public nonisolated func ftpServerSessionUpdated(_ session: FTPSessionInfo) {
        Task { @MainActor in
            if let idx = self.ftpSessions.firstIndex(where: { $0.id == session.id }) {
                self.ftpSessions[idx] = session
            } else {
                self.ftpSessions.insert(session, at: 0)
            }
        }
    }
    
    public nonisolated func ftpServerSessionEnded(sessionId: UUID) {
        Task { @MainActor in
            self.ftpSessions.removeAll(where: { $0.id == sessionId })
        }
    }
    
    public nonisolated func ftpServerStatusChanged(isRunning: Bool, port: Int) {
        Task { @MainActor in
            self.isFTPServerRunning = isRunning
            self.ftpServerConfig.isRunning = isRunning
        }
    }
}

extension AppState: SyslogServerDelegate {
    public nonisolated func syslogServerDidReceive(message: SyslogMessage) {
        Task { @MainActor in
            self.syslogMessages.insert(message, at: 0)
            if self.syslogMessages.count > self.maxSyslogCount {
                self.syslogMessages.removeLast()
            }
        }
    }
    
    public nonisolated func syslogServerDidLog(_ text: String, isError: Bool) {
        Task { @MainActor in
            self.appendGeneralLog("[Syslog] \(text)")
        }
    }
    
    public nonisolated func syslogServerStatusChanged(isRunning: Bool, port: Int) {
        Task { @MainActor in
            self.isSyslogServerRunning = isRunning
            self.syslogConfig.isRunning = isRunning
        }
    }
}
