import Foundation
import SwiftUI

public enum SyslogFacility: Int, Codable, CaseIterable, Identifiable {
    case kern = 0
    case user = 1
    case mail = 2
    case daemon = 3
    case auth = 4
    case syslog = 5
    case lpr = 6
    case news = 7
    case uucp = 8
    case cron = 9
    case authpriv = 10
    case ftp = 11
    case ntp = 12
    case logAudit = 13
    case logAlert = 14
    case clockDaemon = 15
    case local0 = 16
    case local1 = 17
    case local2 = 18
    case local3 = 19
    case local4 = 20
    case local5 = 21
    case local6 = 22
    case local7 = 23
    
    public var id: Int { rawValue }
    
    public var name: String {
        switch self {
        case .kern: return "kern (0)"
        case .user: return "user (1)"
        case .mail: return "mail (2)"
        case .daemon: return "daemon (3)"
        case .auth: return "auth (4)"
        case .syslog: return "syslog (5)"
        case .lpr: return "lpr (6)"
        case .news: return "news (7)"
        case .uucp: return "uucp (8)"
        case .cron: return "cron (9)"
        case .authpriv: return "authpriv (10)"
        case .ftp: return "ftp (11)"
        case .ntp: return "ntp (12)"
        case .logAudit: return "audit (13)"
        case .logAlert: return "alert (14)"
        case .clockDaemon: return "clock (15)"
        case .local0: return "local0 (16)"
        case .local1: return "local1 (17)"
        case .local2: return "local2 (18)"
        case .local3: return "local3 (19)"
        case .local4: return "local4 (20)"
        case .local5: return "local5 (21)"
        case .local6: return "local6 (22)"
        case .local7: return "local7 (23)"
        }
    }
}

public enum SyslogSeverity: Int, Codable, CaseIterable, Identifiable, Comparable {
    case emergency = 0
    case alert = 1
    case critical = 2
    case error = 3
    case warning = 4
    case notice = 5
    case informational = 6
    case debug = 7
    
    public var id: Int { rawValue }
    
    public static func < (lhs: SyslogSeverity, rhs: SyslogSeverity) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
    
    public var name: String {
        switch self {
        case .emergency: return "Emergency (0)"
        case .alert: return "Alert (1)"
        case .critical: return "Critical (2)"
        case .error: return "Error (3)"
        case .warning: return "Warning (4)"
        case .notice: return "Notice (5)"
        case .informational: return "Info (6)"
        case .debug: return "Debug (7)"
        }
    }
    
    public var color: Color {
        switch self {
        case .emergency, .alert:
            return Color.red
        case .critical, .error:
            return Color.orange
        case .warning:
            return Color.yellow
        case .notice:
            return Color.blue
        case .informational:
            return Color.green
        case .debug:
            return Color.secondary
        }
    }
}

public struct SyslogMessage: Identifiable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let sourceIP: String
    public let facility: SyslogFacility
    public let severity: SyslogSeverity
    public let hostname: String
    public let tag: String
    public let message: String
    public let raw: String
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        sourceIP: String,
        facility: SyslogFacility = .local7,
        severity: SyslogSeverity = .informational,
        hostname: String = "",
        tag: String = "",
        message: String,
        raw: String = ""
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sourceIP = sourceIP
        self.facility = facility
        self.severity = severity
        self.hostname = hostname
        self.tag = tag
        self.message = message
        self.raw = raw.isEmpty ? message : raw
    }
    
    public var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}

public struct SyslogConfig: Codable, Equatable {
    public var port: Int = 514
    public var logDirectory: String = (FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.appendingPathComponent("SysTFTP/Syslog").path) ?? "/tmp/SysTFTP/Syslog"
    public var saveToFile: Bool = true
    public var rotateDaily: Bool = true // Daily rotation Month-Day-Year.syslog.log as in 3CDaemon
    public var filterIP: String = ""
    public var isRunning: Bool = false
    
    public init() {}
}
