import Foundation

public enum ServerPortPreset: String, CaseIterable, Identifiable {
    case standard
    case unprivileged

    public var id: String { rawValue }
    public var title: String { self == .standard ? "标准端口" : "普通端口" }
    public var ports: [Int] { self == .standard ? [69, 21, 514] : [6969, 2121, 5140] }
    public var summary: String {
        "TFTP \(ports[0]) · FTP \(ports[1]) · Syslog \(ports[2])"
    }

    public func matches(tftp: Int, ftp: Int, syslog: Int) -> Bool {
        ports == [tftp, ftp, syslog]
    }
}
