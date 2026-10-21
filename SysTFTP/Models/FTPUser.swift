import Foundation
import CryptoKit

public struct FTPUser: Identifiable, Codable, Equatable {
    public var id: String { username }
    public var username: String
    public var passwordHash: String // MD5 hash hex string (compatible with 3CDaemon Profiles.ftp) or plain password
    public var userDirectory: String
    public var canLogin: Bool
    public var canUpload: Bool
    public var canDownload: Bool
    public var canOverwrite: Bool
    public var canDelete: Bool
    public var canRename: Bool
    public var canMkdir: Bool
    public var canRmdir: Bool
    public var isAnonymous: Bool
    
    public init(
        username: String,
        password: String = "",
        userDirectory: String,
        canLogin: Bool = true,
        canUpload: Bool = true,
        canDownload: Bool = true,
        canOverwrite: Bool = true,
        canDelete: Bool = true,
        canRename: Bool = true,
        canMkdir: Bool = true,
        canRmdir: Bool = true,
        isAnonymous: Bool = false
    ) {
        self.username = username
        self.userDirectory = userDirectory
        self.canLogin = canLogin
        self.canUpload = canUpload
        self.canDownload = canDownload
        self.canOverwrite = canOverwrite
        self.canDelete = canDelete
        self.canRename = canRename
        self.canMkdir = canMkdir
        self.canRmdir = canRmdir
        self.isAnonymous = isAnonymous
        
        if isAnonymous {
            self.passwordHash = "NoPassword"
        } else if !password.isEmpty {
            self.passwordHash = FTPUser.hashMD5(password)
        } else {
            self.passwordHash = ""
        }
    }
    
    public static func hashMD5(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02hhX", $0) }.joined()
    }
    
    public func verifyPassword(_ input: String) -> Bool {
        if isAnonymous { return true }
        if passwordHash.isEmpty { return input.isEmpty }
        let hashedInput = FTPUser.hashMD5(input)
        return hashedInput.caseInsensitiveCompare(passwordHash) == .orderedSame || input == passwordHash
    }
}

public struct FTPServerConfig: Codable, Equatable {
    public var port: Int = 21
    public var passivePortRangeStart: Int = 40000
    public var passivePortRangeEnd: Int = 40100
    public var maxIdleTimeoutSeconds: Int = 600 // 10 minutes inactivity timer as in 3CDaemon Rev 7
    public var welcomeBanner: String = "220- Welcome to SysTFTP (3CDaemon macOS Edition)\r\n220 Service ready for new user."
    public var users: [FTPUser] = [
        FTPUser(
            username: "anonymous",
            password: "",
            userDirectory: (FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.appendingPathComponent("SysTFTP/FTP/Public").path) ?? "/tmp/SysTFTP/FTP/Public",
            canLogin: true,
            canUpload: false,
            canDownload: true,
            canOverwrite: false,
            canDelete: false,
            canRename: false,
            canMkdir: false,
            canRmdir: false,
            isAnonymous: true
        ),
        FTPUser(
            username: "admin",
            password: "adminpassword",
            userDirectory: (FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.appendingPathComponent("SysTFTP/FTP/Admin").path) ?? "/tmp/SysTFTP/FTP/Admin",
            canLogin: true,
            canUpload: true,
            canDownload: true,
            canOverwrite: true,
            canDelete: true,
            canRename: true,
            canMkdir: true,
            canRmdir: true,
            isAnonymous: false
        )
    ]
    public var virtualDirectories: [String: String] = [:]
    public var disallowedFiles: [String] = ["3CDaemon.ini", "Profiles.ftp", ".DS_Store", "noaccess.ftp"]
    public var isRunning: Bool = false
    
    public init() {}
}

public struct FTPSessionInfo: Identifiable, Equatable {
    public let id: UUID
    public let clientIP: String
    public let clientPort: UInt16
    public var username: String
    public var currentDirectory: String
    public var isConnected: Bool
    public let connectTime: Date
    public var lastActivityTime: Date
    
    public init(id: UUID = UUID(), clientIP: String, clientPort: UInt16, username: String = "Not logged in", currentDirectory: String = "/", isConnected: Bool = true, connectTime: Date = Date(), lastActivityTime: Date = Date()) {
        self.id = id
        self.clientIP = clientIP
        self.clientPort = clientPort
        self.username = username
        self.currentDirectory = currentDirectory
        self.isConnected = isConnected
        self.connectTime = connectTime
        self.lastActivityTime = lastActivityTime
    }
}
