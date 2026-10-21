import SwiftUI
import AppKit

public struct TFTPServerView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingFolderPicker = false
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Configuration & Control Bar
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TFTP Server")
                            .font(.system(size: 20, weight: .bold))
                        Text("RFC 1350 compliant with RFC 2347, 2348 (blksize), 2349 (timeout, tsize)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        appState.toggleTFTPServer()
                    }) {
                        Label(
                            appState.isTFTPServerRunning ? "Stop Server" : "Start Server",
                            systemImage: appState.isTFTPServerRunning ? "stop.fill" : "play.fill"
                        )
                        .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(appState.isTFTPServerRunning ? .red : .green)
                }
                
                Divider()
                
                // Server Directory Row
                HStack(spacing: 10) {
                    Text("Upload/Download Directory:")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 170, alignment: .leading)
                    
                    TextField("Root Directory", text: $appState.tftpServerConfig.rootDirectory)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                    
                    Button("Browse...") {
                        selectFolder()
                    }
                    
                    Button("Finder") {
                        let url = URL(fileURLWithPath: appState.tftpServerConfig.rootDirectory)
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                    }
                }
                
                // Advanced Options Grid
                HStack(spacing: 24) {
                    Toggle("Allow overwrite of existing files", isOn: $appState.tftpServerConfig.allowOverwrite)
                        .toggleStyle(.checkbox)
                    
                    Toggle("Create directories for incoming requests", isOn: $appState.tftpServerConfig.allowCreateDir)
                        .toggleStyle(.checkbox)
                }
                .font(.system(size: 12))
                
                HStack(spacing: 20) {
                    HStack(spacing: 6) {
                        Text("Port:")
                            .font(.system(size: 12))
                        TextField("69", value: $appState.tftpServerConfig.port, formatter: NumberFormatter())
                            .frame(width: 65)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack(spacing: 6) {
                        Text("Timeout (s):")
                            .font(.system(size: 12))
                        TextField("5", value: $appState.tftpServerConfig.timeoutSeconds, formatter: NumberFormatter())
                            .frame(width: 50)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack(spacing: 6) {
                        Text("Max Retries:")
                            .font(.system(size: 12))
                        TextField("10", value: $appState.tftpServerConfig.maxRetries, formatter: NumberFormatter())
                            .frame(width: 50)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack(spacing: 6) {
                        Text("Frame Gap (ms):")
                            .font(.system(size: 12))
                        TextField("0", value: $appState.tftpServerConfig.frameGapMs, formatter: NumberFormatter())
                            .frame(width: 50)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Transfer List & Log View Split
            HSplitView {
                // Transfers List
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Active & Recent Transfers (\(appState.tftpTransfers.count))")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        if !appState.tftpTransfers.isEmpty {
                            Button("Clear List") {
                                appState.tftpTransfers.removeAll()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    
                    if appState.tftpTransfers.isEmpty {
                        VStack(spacing: 8) {
                            Spacer()
                            Image(systemName: "arrow.up.arrow.down.circle")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("No file transfers yet.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(appState.tftpTransfers) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: item.direction == .upload ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                                        .foregroundColor(item.direction == .upload ? .green : .blue)
                                    
                                    Text(item.filename)
                                        .font(.system(size: 12, weight: .bold))
                                        .lineLimit(1)
                                    
                                    Spacer()
                                    
                                    Text(item.status.rawValue)
                                        .font(.system(size: 10, weight: .semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(statusColor(item.status).opacity(0.15))
                                        .foregroundColor(statusColor(item.status))
                                        .cornerRadius(4)
                                }
                                
                                HStack {
                                    Text("Client: \(item.clientIP):\(item.clientPort)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    if let total = item.totalBytes {
                                        Text("\(formatBytes(item.bytesTransferred)) / \(formatBytes(total))")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("\(formatBytes(item.bytesTransferred))")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                if item.status == .inProgress {
                                    ProgressView(value: item.progress)
                                        .progressViewStyle(.linear)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listStyle(.inset)
                    }
                }
                .frame(minWidth: 320)
                
                // Server Console Log
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("TFTP Activity Log")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button("Clear") {
                            appState.tftpLogs.removeAll()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(appState.tftpLogs.enumerated()), id: \.offset) { idx, line in
                                    Text(line)
                                        .font(.system(size: 11, design: .monospaced))
                                        .textSelection(.enabled)
                                        .id(idx)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                        .onChange(of: appState.tftpLogs.count) { _ in
                            if let last = appState.tftpLogs.indices.last {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                }
                .frame(minWidth: 300)
            }
        }
    }
    
    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose TFTP Root"
        if panel.runModal() == .OK, let url = panel.url {
            appState.tftpServerConfig.rootDirectory = url.path
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
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
