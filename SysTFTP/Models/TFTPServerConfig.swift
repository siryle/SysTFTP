import Foundation

public struct TFTPServerConfig: Codable, Equatable {
    public var port: Int = 69
    public var rootDirectory: String = (FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.appendingPathComponent("SysTFTP/TFTP").path) ?? "/tmp/SysTFTP/TFTP"
    public var allowOverwrite: Bool = false
    public var allowCreateDir: Bool = true
    public var timeoutSeconds: Int = 5
    public var maxRetries: Int = 10
    public var frameGapMs: Int = 0
    public var isRunning: Bool = false
    
    public init() {}
}

public enum TFTPTransferDirection: String, Codable {
    case upload = "Upload (WRQ)"
    case download = "Download (RRQ)"

    public var displayName: String {
        switch self {
        case .upload: return "上传（WRQ）"
        case .download: return "下载（RRQ）"
        }
    }
}

public enum TFTPTransferStatus: String, Codable {
    case inProgress = "Transferring"
    case completed = "Completed"
    case failed = "Failed"
    case aborted = "Aborted"

    public var displayName: String {
        switch self {
        case .inProgress: return "传输中"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .aborted: return "已取消"
        }
    }
}

public struct TFTPTransferItem: Identifiable, Equatable {
    public let id: UUID
    public let filename: String
    public let clientIP: String
    public let clientPort: UInt16
    public let direction: TFTPTransferDirection
    public var bytesTransferred: Int64
    public var totalBytes: Int64?
    public var progress: Double {
        guard let total = totalBytes, total > 0 else { return 0 }
        return min(1.0, Double(bytesTransferred) / Double(total))
    }
    public var speedBytesPerSec: Double
    public var status: TFTPTransferStatus
    public var errorMessage: String?
    public let startTime: Date
    public var endTime: Date?
    
    public init(id: UUID = UUID(), filename: String, clientIP: String, clientPort: UInt16, direction: TFTPTransferDirection, bytesTransferred: Int64 = 0, totalBytes: Int64? = nil, speedBytesPerSec: Double = 0, status: TFTPTransferStatus = .inProgress, errorMessage: String? = nil, startTime: Date = Date(), endTime: Date? = nil) {
        self.id = id
        self.filename = filename
        self.clientIP = clientIP
        self.clientPort = clientPort
        self.direction = direction
        self.bytesTransferred = bytesTransferred
        self.totalBytes = totalBytes
        self.speedBytesPerSec = speedBytesPerSec
        self.status = status
        self.errorMessage = errorMessage
        self.startTime = startTime
        self.endTime = endTime
    }
}
