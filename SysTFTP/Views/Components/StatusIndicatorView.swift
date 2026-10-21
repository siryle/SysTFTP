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
    
    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "network")
                .foregroundColor(.accentColor)
            
            Text("Local IP:")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            
            if networkMonitor.interfaces.isEmpty {
                Text("Detecting...")
                    .font(.system(size: 12))
            } else {
                ForEach(networkMonitor.interfaces.filter { !$0.isLoopback }.prefix(2)) { iface in
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(iface.ipAddress, forType: .string)
                        copiedMessage = iface.ipAddress
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copiedMessage = nil
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text(iface.name)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                            Text(iface.ipAddress)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            Image(systemName: copiedMessage == iface.ipAddress ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10))
                                .foregroundColor(copiedMessage == iface.ipAddress ? .green : .secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help("Click to copy \(iface.ipAddress)")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
        .cornerRadius(8)
    }
}
