import SwiftUI
import AppKit

public struct TFTPClientView: View {
    @EnvironmentObject var appState: AppState

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            PageHeaderView(
                title: "TFTP 客户端",
                subtitle: "与路由器、交换机及嵌入式设备交换文件"
            ) {
                HStack(spacing: 10) {
                    Button(action: { appState.startClientTransfer() }) {
                        Label("开始传输", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.isClientTransferring || appState.tftpClientConfig.remoteFilePath.isEmpty)

                    Button(action: { appState.cancelClientTransfer() }) {
                        Label("停止", systemImage: "stop.fill")
                    }
                    .disabled(!appState.isClientTransferring)
                }
                .controlSize(.large)
            }

            Divider()
            progressSection
            Divider()

            VSplitView {
                GeometryReader { geometry in
                    ScrollView {
                        Group {
                            if geometry.size.width >= 800 {
                                HStack(alignment: .top, spacing: 16) {
                                    connectionSection
                                    negotiationSection
                                        .frame(width: 250)
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 16) {
                                    connectionSection
                                    negotiationSection
                                }
                            }
                        }
                        .padding(20)
                    }
                }
                .frame(minHeight: 200, idealHeight: 450, maxHeight: .infinity)

                ConsoleLogView(title: "客户端传输日志", lines: appState.tftpClientLogs) {
                    appState.tftpClientLogs.removeAll()
                }
                .frame(minHeight: 140, idealHeight: 170, maxHeight: 220)
            }
        }
    }

    private var connectionSection: some View {
        FormSectionView(title: "连接与文件") {
            HStack(alignment: .top, spacing: 16) {
                FormFieldView(title: "服务器地址") {
                    HStack(spacing: 8) {
                        TextField("例如 192.168.1.1", text: $appState.tftpClientConfig.serverHost)
                            .font(.system(size: 13, design: .monospaced))
                        Menu("最近主机") {
                            ForEach(appState.tftpClientConfig.recentServers, id: \.self) { server in
                                Button(server) { appState.tftpClientConfig.serverHost = server }
                            }
                        }
                        .fixedSize()
                    }
                }
                FormFieldView(title: "UDP 端口") {
                    TextField("69", value: $appState.tftpClientConfig.serverPort, formatter: NumberFormatter())
                }
                .frame(width: 88)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 16)], alignment: .leading, spacing: 16) {
                FormFieldView(title: "传输方向") {
                    Picker("传输方向", selection: $appState.tftpClientConfig.isUpload) {
                        Text("上传文件").tag(true)
                        Text("下载文件").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            FormFieldView(title: "远程文件名") {
                TextField("服务器上的文件名，例如 firmware.bin", text: $appState.tftpClientConfig.remoteFilePath)
                    .font(.system(size: 13, design: .monospaced))
            }

            FormFieldView(title: appState.tftpClientConfig.isUpload ? "本地源文件" : "本地保存位置") {
                HStack(spacing: 10) {
                    TextField("本机文件路径", text: $appState.tftpClientConfig.localFilePath)
                        .font(.system(size: 13, design: .monospaced))
                        .help(appState.tftpClientConfig.localFilePath)
                    Button("浏览…") {
                        if appState.tftpClientConfig.isUpload {
                            selectLocalFileForUpload()
                        } else {
                            selectLocalFileForDownload()
                        }
                    }
                    .fixedSize()
                }
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private var negotiationSection: some View {
        FormSectionView(title: "协议协商") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 20)], alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("协商块大小", isOn: $appState.tftpClientConfig.enableBlockSizeNegotiation)
                    HStack(spacing: 8) {
                        TextField("1428", value: $appState.tftpClientConfig.blockSize, formatter: NumberFormatter())
                            .frame(width: 76)
                        Text("字节")
                            .foregroundColor(.secondary)
                    }
                    .disabled(!appState.tftpClientConfig.enableBlockSizeNegotiation)
                    Text("RFC 2348 · 512–65464 字节")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Toggle("协商超时时间", isOn: $appState.tftpClientConfig.enableTimeoutNegotiation)
                    HStack(spacing: 8) {
                        TextField("5", value: $appState.tftpClientConfig.timeoutSeconds, formatter: NumberFormatter())
                            .frame(width: 76)
                        Text("秒")
                            .foregroundColor(.secondary)
                    }
                    .disabled(!appState.tftpClientConfig.enableTimeoutNegotiation)
                    Text("RFC 2349 · timeout")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Toggle("协商传输大小", isOn: $appState.tftpClientConfig.enableTransferSizeNegotiation)
                    Text("获取文件总大小，显示传输进度。")
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("RFC 2349 · tsize")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .font(.system(size: 12))
            .toggleStyle(.checkbox)
            .textFieldStyle(.roundedBorder)
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appState.clientStatusMessage)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .textSelection(.enabled)
                .help(appState.clientStatusMessage)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 16) {
                ProgressView(value: appState.clientTransferProgress)
                    .progressViewStyle(.linear)
                if let total = appState.clientTotalBytes, total > 0 {
                    Text("\(formatBytes(appState.clientTransferredBytes)) / \(formatBytes(total)) · \(Int(appState.clientTransferProgress * 100))%")
                        .fixedSize()
                } else {
                    Text("已传输 \(formatBytes(appState.clientTransferredBytes))")
                        .fixedSize()
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func selectLocalFileForUpload() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "选择要发送的文件"
        panel.prompt = "选择文件"
        if panel.runModal() == .OK, let url = panel.url {
            appState.tftpClientConfig.localFilePath = url.path
            if appState.tftpClientConfig.remoteFilePath.isEmpty {
                appState.tftpClientConfig.remoteFilePath = url.lastPathComponent
            }
        }
    }

    private func selectLocalFileForDownload() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = appState.tftpClientConfig.remoteFilePath.isEmpty ? "downloaded_file.bin" : (appState.tftpClientConfig.remoteFilePath as NSString).lastPathComponent
        panel.title = "保存接收文件"
        panel.prompt = "保存"
        if panel.runModal() == .OK, let url = panel.url {
            appState.tftpClientConfig.localFilePath = url.path
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowsNonnumericFormatting = false
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
