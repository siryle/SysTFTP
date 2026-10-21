import Foundation

public struct NetworkInterfaceInfo: Identifiable, Hashable {
    public var id: String { name }
    public let name: String
    public let ipAddress: String
    public let isUp: Bool
    public let isLoopback: Bool
    
    public var displayName: String {
        let typeName: String
        if name.hasPrefix("en0") {
            typeName = "Wi-Fi (en0)"
        } else if name.hasPrefix("en") {
            typeName = "以太网（\(name)）"
        } else if name.hasPrefix("bridge") || name.hasPrefix("ap") {
            typeName = "网桥 / 热点（\(name)）"
        } else if name.hasPrefix("utun") || name.hasPrefix("tun") {
            typeName = "VPN (\(name))"
        } else if name == "lo0" {
            typeName = "本地回环"
        } else {
            typeName = name
        }
        return "\(typeName): \(ipAddress)"
    }
}
