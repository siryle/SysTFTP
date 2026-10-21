import SwiftUI

public struct StatusIndicatorView: View {
    public let isRunning: Bool
    public let title: String
    public let subtitle: String?
    
    public init(isRunning: Bool, title: String, subtitle: String? = nil) {
        self.isRunning = isRunning
        self.title = title
        self.subtitle = subtitle
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isRunning ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(isRunning ? Color.green.opacity(0.4) : Color.clear, lineWidth: 3)
                        .scaleEffect(isRunning ? 1.4 : 1.0)
                )
                .animation(isRunning ? Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true) : .default, value: isRunning)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

public struct NetworkBadgeView: View {
    @ObservedObject var networkMonitor = NetworkMonitorService.shared
    @State private var copiedMessage: String?

    public init() {}

    private var primaryInterface: NetworkInterfaceInfo? {
        networkMonitor.interfaces.first(where: { !$0.isLoopback }) ?? networkMonitor.interfaces.first
    }

    public var body: some View {
        HStack(spacing: 8) {
            if let interface = primaryInterface {
                Button(action: { copyAddress(interface.ipAddress) }) {
                    HStack(spacing: 7) {
                        Image(systemName: copiedMessage == interface.ipAddress ? "checkmark" : "network")
                            .foregroundColor(copiedMessage == interface.ipAddress ? .green : .accentColor)
                        Text(interface.ipAddress)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                }
                .buttonStyle(.plain)
                .help("\(interface.displayName) · 点击复制 IP")
                .accessibilityLabel("复制本机 IP：\(interface.ipAddress)")

                if networkMonitor.interfaces.count > 1 {
                    Menu {
                        ForEach(networkMonitor.interfaces) { interface in
                            Button(interface.displayName) { copyAddress(interface.ipAddress) }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("查看并复制其他网卡地址")
                    .accessibilityLabel("其他网卡地址")
                }
            } else {
                Label("正在检测网络…", systemImage: "network")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(7)
    }

    private func copyAddress(_ address: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(address, forType: .string)
        copiedMessage = address
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedMessage == address { copiedMessage = nil }
        }
    }
}
