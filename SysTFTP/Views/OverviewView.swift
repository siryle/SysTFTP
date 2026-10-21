import SwiftUI

public struct OverviewView: View {
    @EnvironmentObject var appState: AppState
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Banner
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SysTFTP Dashboard")
                            .font(.system(size: 24, weight: .bold))
                        Text("3CDaemon Remastered for macOS - TFTP, FTP & Syslog Server Suite")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            appState.startAllServices()
                        }) {
                            Label("Start All", systemImage: "play.fill")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        
                        Button(action: {
                            appState.stopAllServices()
                        }) {
                            Label("Stop All", systemImage: "stop.fill")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
                .padding(.bottom, 8)
                
                // 4 Service Grid Cards
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    // TFTP Server Card
                    ServiceCardView(
                        title: "TFTP Server",
                        subtitle: "RFC 1350 / 2347 / 2348 / 2349",
                        icon: "server.rack",
                        color: .blue,
                        isRunning: appState.isTFTPServerRunning,
                        details: [
                            ("Port", "\(appState.tftpServerConfig.port) (UDP)"),
                            ("Root Dir", URL(fileURLWithPath: appState.tftpServerConfig.rootDirectory).lastPathComponent),
                            ("Active Transfers", "\(appState.tftpTransfers.filter { $0.status == .inProgress }.count)")
                        ],
                        onToggle: { appState.toggleTFTPServer() },
                        onNavigate: { appState.selectedItem = .tftpServer }
                    )
                    
                    // FTP Server Card
                    ServiceCardView(
                        title: "FTP Server",
                        subtitle: "RFC 959 with PASV & User Accounts",
                        icon: "externaldrive.connected.to.line.below",
                        color: .teal,
                        isRunning: appState.isFTPServerRunning,
                        details: [
                            ("Port", "\(appState.ftpServerConfig.port) (TCP)"),
                            ("Configured Users", "\(appState.ftpServerConfig.users.count)"),
                            ("Active Clients", "\(appState.ftpSessions.count)")
                        ],
                        onToggle: { appState.toggleFTPServer() },
                        onNavigate: { appState.selectedItem = .ftpServer }
                    )
                    
                    // Syslog Server Card
                    ServiceCardView(
                        title: "Syslog Server",
                        subtitle: "RFC 3164 / 5424 Daemon & Realtime Viewer",
                        icon: "waveform.path.ecg.rectangle",
                        color: .purple,
                        isRunning: appState.isSyslogServerRunning,
                        details: [
                            ("Port", "\(appState.syslogConfig.port) (UDP)"),
                            ("Daily Rotation", appState.syslogConfig.rotateDaily ? "Enabled" : "Disabled"),
                            ("Received Events", "\(appState.syslogMessages.count)")
                        ],
                        onToggle: { appState.toggleSyslogServer() },
                        onNavigate: { appState.selectedItem = .syslogServer }
                    )
                    
                    // TFTP Client Card
                    ServiceCardView(
                        title: "TFTP Client",
                        subtitle: "File Upload & Download Tool",
                        icon: "arrow.up.arrow.down.circle",
                        color: .cyan,
                        isRunning: appState.isClientTransferring,
                        details: [
                            ("Target Host", appState.tftpClientConfig.serverHost),
                            ("Direction", appState.tftpClientConfig.isUpload ? "Upload" : "Download"),
                            ("Status", appState.clientStatusMessage)
                        ],
                        onToggle: {
                            if appState.isClientTransferring {
                                appState.cancelClientTransfer()
                            } else {
                                appState.selectedItem = .tftpClient
                            }
                        },
                        toggleButtonLabel: appState.isClientTransferring ? "Stop" : "Open",
                        onNavigate: { appState.selectedItem = .tftpClient }
                    )
                }
                
                // Network Interfaces Information Panel
                VStack(alignment: .leading, spacing: 12) {
                    Text("Detected Network Adapters & Addresses")
                        .font(.system(size: 15, weight: .semibold))
                    
                    Text("Configure your Cisco, Huawei, H3C or Linux devices to point to one of these server IP addresses:")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                        ForEach(appState.networkMonitor.interfaces) { iface in
                            HStack {
                                Image(systemName: iface.name.hasPrefix("en0") ? "wifi" : (iface.isLoopback ? "arrow.triangle.2.circlepath" : "cable.connector"))
                                    .foregroundColor(.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(iface.name)
                                        .font(.system(size: 12, weight: .bold))
                                    Text(iface.ipAddress)
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                }
                                Spacer()
                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(iface.ipAddress, forType: .string)
                                }) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.plain)
                                .help("Copy IP")
                            }
                            .padding(10)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(12)
                
                // Recent System Log Stream preview
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Recent System Activity")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        if appState.tftpLogs.isEmpty && appState.ftpLogs.isEmpty && appState.generalLogs.isEmpty {
                            Text("No recent log activity. Start a service to begin.")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            let recentLogs = (appState.tftpLogs.suffix(4) + appState.ftpLogs.suffix(4) + appState.generalLogs.suffix(4)).suffix(6)
                            ForEach(Array(recentLogs), id: \.self) { line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
            .padding(24)
        }
    }
}

private struct ServiceCardView: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let isRunning: Bool
    let details: [(String, String)]
    let onToggle: () -> Void
    var toggleButtonLabel: String? = nil
    let onNavigate: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(color)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 16, weight: .bold))
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(isRunning ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 8, height: 8)
                    Text(isRunning ? "Running" : "Stopped")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isRunning ? .green : .secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(12)
            }
            
            Divider()
            
            VStack(spacing: 6) {
                ForEach(details, id: \.0) { item in
                    HStack {
                        Text(item.0)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(item.1)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                    }
                }
            }
            
            HStack {
                Button(action: onNavigate) {
                    Text("Configure")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                
                Spacer()
                
                Button(action: onToggle) {
                    Text(toggleButtonLabel ?? (isRunning ? "Stop" : "Start"))
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .tint(isRunning ? .red : .green)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 3)
    }
}
