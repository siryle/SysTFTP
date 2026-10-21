import Foundation

public struct TFTPClientConfig: Codable, Equatable {
    public var serverHost: String = "192.168.1.1"
    public var serverPort: Int = 69
    public var isUpload: Bool = false
    public var mode: String = "octet" // "octet" or "netascii"
    public var localFilePath: String = ""
    public var remoteFilePath: String = "firmware.bin"
    
    // RFC 2348 Block Size
    public var enableBlockSizeNegotiation: Bool = true
    public var blockSize: Int = 1428 // Common optimal MTU fit
    
    // RFC 2349 Timeout
    public var enableTimeoutNegotiation: Bool = true
    public var timeoutSeconds: Int = 5
    
    // RFC 2349 Transfer Size
    public var enableTransferSizeNegotiation: Bool = true
    
    public var recentServers: [String] = ["192.168.1.1", "192.168.0.1", "10.0.0.1", "127.0.0.1"]
    
    public init() {}
}
