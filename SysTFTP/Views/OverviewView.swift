import SwiftUI

public struct OverviewView: View {
    @EnvironmentObject var appState: AppState
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            PageHeaderView(
                title: "SysTFTP 控制台",
                subtitle: "macOS 版 3CDaemon · TFTP、FTP 与 Syslog 网络工具套件"
            ) {
                HStack(spacing: 10) {
                    Button(action: { appState.startAllServices() }) {
                        Label("全部启动", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    Button(action: { appState.stopAllServices() }) {
                        Label("全部停止", systemImage: "stop.fill")
                    }
                    .tint(.red)
                }
                .controlSize(.large)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 4 Service Grid Cards
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                        // TFTP Server Card
                        ServiceCardView(
                            title: "TFTP 服务器",
                            subtitle: "RFC 1350 / 2347 / 2348 / 2349",
                            icon: "server.rack",
                            color: .blue,
                            isRunning: appState.isTFTPServerRunning,
                            details: [
                                ("端口", "\(appState.tftpServerConfig.port) (UDP)"),
                                ("根目录", URL(fileURLWithPath: appState.tftpServerConfig.rootDirectory).lastPathComponent),
                                ("正在传输", "\(appState.tftpTransfers.filter { $0.status == .inProgress }.count)")
                            ],
                            onToggle: { appState.toggleTFTPServer() },
                            onNavigate: { appState.selectedItem = .tftpServer }
                        )
                    
                        // FTP Server Card
                        ServiceCardView(
                            title: "FTP 服务器",
                            subtitle: "RFC 959 · 被动模式与用户管理",
                            icon: "externaldrive.connected.to.line.below",
                            color: .teal,
                            isRunning: appState.isFTPServerRunning,
                            details: [
                                ("端口", "\(appState.ftpServerConfig.port) (TCP)"),
                                ("已配置用户", "\(appState.ftpServerConfig.users.count)"),
                                ("在线客户端", "\(appState.ftpSessions.count)")
                            ],
                            onToggle: { appState.toggleFTPServer() },
                            onNavigate: { appState.selectedItem = .ftpServer }
                        )
                    
                        // Syslog Server Card
                        ServiceCardView(
                            title: "Syslog 日志服务器",
                            subtitle: "RFC 3164 / 5424 · 日志接收与实时查看",
                            icon: "waveform.path.ecg.rectangle",
                            color: .purple,
                            isRunning: appState.isSyslogServerRunning,
                            details: [
                                ("端口", "\(appState.syslogConfig.port) (UDP)"),
                                ("按日轮转", appState.syslogConfig.rotateDaily ? "已启用" : "已禁用"),
                                ("已接收事件", "\(appState.syslogMessages.count)")
                            ],
                            onToggle: { appState.toggleSyslogServer() },
                            onNavigate: { appState.selectedItem = .syslogServer }
                        )
                    
                        // TFTP Client Card
                        ServiceCardView(
                            title: "TFTP 客户端",
                            subtitle: "文件上传与下载工具",
                            icon: "arrow.up.arrow.down.circle",
                            color: .cyan,
                            isRunning: appState.isClientTransferring,
                            details: [
                                ("目标主机", appState.tftpClientConfig.serverHost),
                                ("传输方向", appState.tftpClientConfig.isUpload ? "上传" : "下载"),
                                ("状态", appState.clientStatusMessage)
                            ],
                            onToggle: {
                                if appState.isClientTransferring {
                                    appState.cancelClientTransfer()
                                } else {
                                    appState.selectedItem = .tftpClient
                                }
                            },
                            toggleButtonLabel: appState.isClientTransferring ? "停止" : "打开",
                            onNavigate: { appState.selectedItem = .tftpClient }
                        )
                    }
                
                    // Network Interfaces Information Panel
                    VStack(alignment: .leading, spacing: 12) {
                        Text("网络适配器与 IP 地址")
                            .font(.system(size: 15, weight: .semibold))
                    
                        Text("请在 Cisco、华为、H3C 或 Linux 设备上，将服务器地址配置为以下任一 IP：")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    
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
                                    .help("复制 IP 地址")
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
                            Text("最近系统活动")
                                .font(.system(size: 15, weight: .semibold))
                            Spacer()
                        }
                    
                        VStack(alignment: .leading, spacing: 4) {
                            if appState.tftpLogs.isEmpty && appState.ftpLogs.isEmpty && appState.generalLogs.isEmpty {
                                Text("暂无日志，请先启动服务。")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 8)
                            } else {
                                let recentLogs = (appState.tftpLogs.suffix(4) + appState.ftpLogs.suffix(4) + appState.generalLogs.suffix(4)).suffix(6)
                                ForEach(Array(recentLogs), id: \.self) { line in
                                    Text(line)
                                        .font(.system(size: 12, design: .monospaced))
                                        .lineLimit(2)
                                        .lineSpacing(3)
                                        .help(line)
                                }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                .padding(20)
            }
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
                Image(systemName: icon)
                    .font(.system(size: 21))
                    .foregroundColor(color)
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(isRunning ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 7, height: 7)
                    Text(isRunning ? "运行中" : "已停止")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isRunning ? .green : .secondary)
                }
                .fixedSize()
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(12)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .lineSpacing(3)
                    .frame(minHeight: 34, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
            
            VStack(spacing: 6) {
                ForEach(details, id: \.0) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(item.0)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .fixedSize()
                        Spacer(minLength: 0)
                        Text(item.1)
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                            .help(item.1)
                    }
                }
            }
            
            HStack {
                Button(action: onNavigate) {
                    Text("配置")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                
                Spacer()
                
                Button(action: onToggle) {
                    Text(toggleButtonLabel ?? (isRunning ? "停止" : "启动"))
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
