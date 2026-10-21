import SwiftUI
import AppKit

public struct TFTPClientView: View {
    @EnvironmentObject var appState: AppState
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Configuration Form
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TFTP Client")
                            .font(.system(size: 20, weight: .bold))
                        Text("Exchange files with remote TFTP servers (Routers, Switches, Embedded devices)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            appState.startClientTransfer()
                        }) {
                            Label("GO", systemImage: "play.fill")
                                .font(.system(size: 13, weight: .bold))
                                .frame(width: 80)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .disabled(appState.isClientTransferring || appState.tftpClientConfig.remoteFilePath.isEmpty)
                        
                        Button(action: {
                            appState.cancelClientTransfer()
                        }) {
                            Label("STOP", systemImage: "stop.fill")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(!appState.isClientTransferring)
                    }
                }
                
                Divider()
                
                // Server Address and Port
                HStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Text("Server Address:")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 120, alignment: .leading)
                        
                        TextField("e.g. 192.168.1.1", text: $appState.tftpClientConfig.serverHost)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    
                    HStack(spacing: 6) {
                        Text("Port:")
                            .font(.system(size: 12))
                        TextField("69", value: $appState.tftpClientConfig.serverPort, formatter: NumberFormatter())
                            .frame(width: 65)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    // Quick Host History Menu
                    Menu("Recent Hosts") {
                        ForEach(appState.tftpClientConfig.recentServers, id: \.self) { server in
                            Button(server) {
                                appState.tftpClientConfig.serverHost = server
                            }
                        }
                    }
                }
                
                // Direction and Mode
                HStack(spacing: 32) {
                    Picker("Operation:", selection: $appState.tftpClientConfig.isUpload) {
                        Text("Send File (Upload)").tag(true)
                        Text("Receive File (Download)").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 300)
                    
                    Picker("Mode:", selection: $appState.tftpClientConfig.mode) {
                        Text("Octet (Binary)").tag("octet")
                        Text("NetAscii (Text)").tag("netascii")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
                
                // Remote and Local File Paths
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Text("Remote File Name:")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 120, alignment: .leading)
                        TextField("filename on TFTP server (e.g. c2960-lanbasek9-mz.150-2.SE4.bin)", text: $appState.tftpClientConfig.remoteFilePath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    
                    HStack(spacing: 8) {
                        Text("Local File Name:")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 120, alignment: .leading)
                        TextField("Path on local Mac disk", text: $appState.tftpClientConfig.localFilePath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                        
                        Button("Browse...") {
                            if appState.tftpClientConfig.isUpload {
                                selectLocalFileForUpload()
                            } else {
                                selectLocalFileForDownload()
                            }
                        }
                    }
                }
                
                // RFC Options Negotiation Box
                VStack(alignment: .leading, spacing: 8) {
                    Text("Protocol Negotiation Options:")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 24) {
                        Toggle("RFC 2348 Block Size", isOn: $appState.tftpClientConfig.enableBlockSizeNegotiation)
                            .toggleStyle(.checkbox)
                        
                        HStack(spacing: 4) {
                            Text("Block Size:")
                            TextField("1428", value: $appState.tftpClientConfig.blockSize, formatter: NumberFormatter())
                                .frame(width: 60)
                                .textFieldStyle(.roundedBorder)
                            Text("bytes (512-65464)")
                                .foregroundColor(.secondary)
                        }
                        .disabled(!appState.tftpClientConfig.enableBlockSizeNegotiation)
                        
                        Toggle("RFC 2349 Timeout", isOn: $appState.tftpClientConfig.enableTimeoutNegotiation)
                            .toggleStyle(.checkbox)
                        
                        HStack(spacing: 4) {
                            Text("Seconds:")
                            TextField("5", value: $appState.tftpClientConfig.timeoutSeconds, formatter: NumberFormatter())
                                .frame(width: 45)
                                .textFieldStyle(.roundedBorder)
                        }
                        .disabled(!appState.tftpClientConfig.enableTimeoutNegotiation)
                        
                        Toggle("RFC 2349 Transfer Size (tsize)", isOn: $appState.tftpClientConfig.enableTransferSizeNegotiation)
                            .toggleStyle(.checkbox)
                    }
                    .font(.system(size: 11))
                }
                .padding(10)
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(8)
                
                // Progress Bar and Speed
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(appState.clientStatusMessage)
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        if let total = appState.clientTotalBytes, total > 0 {
                            Text("\(formatBytes(appState.clientTransferredBytes)) / \(formatBytes(total)) (\(Int(appState.clientTransferProgress * 100))%)")
                                .font(.system(size: 12, design: .monospaced))
                        } else {
                            Text("\(formatBytes(appState.clientTransferredBytes)) transferred")
                                .font(.system(size: 12, design: .monospaced))
                        }
                    }
                    
                    ProgressView(value: appState.clientTransferProgress)
                        .progressViewStyle(.linear)
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Client Console Log
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Client Transfer Log")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button("Clear") {
                        appState.tftpClientLogs.removeAll()
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
                            ForEach(Array(appState.tftpClientLogs.enumerated()), id: \.offset) { idx, line in
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
                    .onChange(of: appState.tftpClientLogs.count) { _ in
                        if let last = appState.tftpClientLogs.indices.last {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
    
    private func selectLocalFileForUpload() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select File to Send"
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
        panel.prompt = "Save Received File As"
        if panel.runModal() == .OK, let url = panel.url {
            appState.tftpClientConfig.localFilePath = url.path
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
