import SwiftUI
import AppKit

public struct TFTPServerView: View {
    @EnvironmentObject var appState: AppState
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            PageHeaderView(
                title: "TFTP 服务器",
                subtitle: "RFC 1350 / 2347 / 2348 / 2349 · 文件传输与选项协商"
            ) {
                Button(action: { appState.toggleTFTPServer() }) {
                    Label(
                        appState.isTFTPServerRunning ? "停止服务" : "启动服务",
                        systemImage: appState.isTFTPServerRunning ? "stop.fill" : "play.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(appState.isTFTPServerRunning ? .red : .green)
            }

            Divider()

            VSplitView {
                ScrollView {
                    configuration
                        .padding(20)
                }
                .frame(minHeight: 160, idealHeight: 255)

                HSplitView {
                    transferList
                        .frame(minWidth: 280)
                    ConsoleLogView(title: "TFTP 活动日志", lines: appState.tftpLogs) {
                        appState.tftpLogs.removeAll()
                    }
                    .frame(minWidth: 280)
                }
                .frame(minHeight: 180)
            }
        }
    }

    private var configuration: some View {
        VStack(alignment: .leading, spacing: 20) {
            FormFieldView(title: "上传 / 下载目录") {
                HStack(spacing: 10) {
                    TextField("根目录", text: $appState.tftpServerConfig.rootDirectory)
                        .font(.system(size: 13, design: .monospaced))
                        .help(appState.tftpServerConfig.rootDirectory)
                    Button("浏览…", action: selectFolder)
                        .fixedSize()
                    Button(action: {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: appState.tftpServerConfig.rootDirectory)
                    }) {
                        Label("在访达中打开", systemImage: "folder")
                    }
                    .fixedSize()
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 16)], alignment: .leading, spacing: 12) {
                Toggle("允许覆盖已有文件", isOn: $appState.tftpServerConfig.allowOverwrite)
                Toggle("允许为上传请求创建目录", isOn: $appState.tftpServerConfig.allowCreateDir)
            }
            .toggleStyle(.checkbox)
            .font(.system(size: 12))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 16)], alignment: .leading, spacing: 16) {
                FormFieldView(title: "UDP 端口") {
                    TextField("69", value: $appState.tftpServerConfig.port, formatter: NumberFormatter())
                }
                FormFieldView(title: "超时时间（秒）") {
                    TextField("5", value: $appState.tftpServerConfig.timeoutSeconds, formatter: NumberFormatter())
                }
                FormFieldView(title: "最大重试次数") {
                    TextField("10", value: $appState.tftpServerConfig.maxRetries, formatter: NumberFormatter())
                }
                FormFieldView(title: "帧间隔（毫秒）") {
                    TextField("0", value: $appState.tftpServerConfig.frameGapMs, formatter: NumberFormatter())
                }
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private var transferList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("传输记录（\(appState.tftpTransfers.count)）")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("清空") { appState.tftpTransfers.removeAll() }
                    .controlSize(.small)
                    .disabled(appState.tftpTransfers.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            if appState.tftpTransfers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.up.arrow.down.circle")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("暂无文件传输")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(appState.tftpTransfers) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: item.direction == .upload ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                                .foregroundColor(item.direction == .upload ? .green : .blue)
                            Text(item.filename)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(2)
                                .help(item.filename)
                            Spacer(minLength: 4)
                            Text(item.status.displayName)
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(statusColor(item.status).opacity(0.15))
                                .foregroundColor(statusColor(item.status))
                                .cornerRadius(5)
                                .fixedSize()
                        }
                        Text("客户端：\(item.clientIP):\(String(item.clientPort))")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                        if let total = item.totalBytes {
                            Text("\(formatBytes(item.bytesTransferred)) / \(formatBytes(total))")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                        } else {
                            Text(formatBytes(item.bytesTransferred))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        if item.status == .inProgress {
                            ProgressView(value: item.progress)
                                .progressViewStyle(.linear)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .listStyle(.inset)
            }
        }
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "选择 TFTP 根目录"
        panel.prompt = "选择目录"
        if panel.runModal() == .OK, let url = panel.url {
            appState.tftpServerConfig.rootDirectory = url.path
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowsNonnumericFormatting = false
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func statusColor(_ status: TFTPTransferStatus) -> Color {
        switch status {
        case .completed: return .green
        case .inProgress: return .blue
        case .failed: return .red
        case .aborted: return .orange
        }
    }
}
