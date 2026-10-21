import SwiftUI

public struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var launchAtLogin = false
    @State private var showInMenuBar = true
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("SysTFTP Settings")
                    .font(.system(size: 22, weight: .bold))
                
                // Port Profile Presets
                VStack(alignment: .leading, spacing: 12) {
                    Text("Port Presets & Privileges")
                        .font(.system(size: 15, weight: .semibold))
                    
                    Text("macOS restricts ports below 1024 (TFTP: 69, FTP: 21, Syslog: 514) to root processes or requires running with elevated privileges. You can easily switch between standard and non-privileged ports:")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 16) {
                        Button(action: {
                            appState.tftpServerConfig.port = 69
                            appState.ftpServerConfig.port = 21
                            appState.syslogConfig.port = 514
                        }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Standard Ports (Root)")
                                    .font(.system(size: 13, weight: .bold))
                                Text("TFTP: 69 | FTP: 21 | Syslog: 514")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: {
                            appState.tftpServerConfig.port = 6969
                            appState.ftpServerConfig.port = 2121
                            appState.syslogConfig.port = 5140
                        }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Non-Privileged Ports")
                                    .font(.system(size: 13, weight: .bold))
                                Text("TFTP: 6969 | FTP: 2121 | Syslog: 5140")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                
                // System Tray / Menu Bar Extra
                VStack(alignment: .leading, spacing: 12) {
                    Text("System Integration")
                        .font(.system(size: 15, weight: .semibold))
                    
                    Toggle("Show SysTFTP icon in macOS Menu Bar (System Tray)", isOn: $showInMenuBar)
                    Toggle("Start minimized to Menu Bar on launch", isOn: .constant(false))
                    Toggle("Keep system awake while file transfers are active", isOn: .constant(true))
                }
                .font(.system(size: 13))
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                
                // About Section
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        Image(nsImage: NSImage(contentsOfFile: Bundle.main.path(forResource: "AppIcon", ofType: "icns") ?? "") ?? NSImage())
                            .resizable()
                            .frame(width: 48, height: 48)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SysTFTP for macOS")
                                .font(.system(size: 16, weight: .bold))
                            Text("Version 1.0.0 (Build 2026.10)")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Text("SysTFTP is a modern native macOS recreation of 3Com's legendary 3CDaemon tool. Designed for network engineers, IT professionals, and embedded developers working on macOS.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    Text("RFC Standards Supported: RFC 1350 (TFTP), RFC 2347 (Option Extension), RFC 2348 (Blocksize Option), RFC 2349 (Timeout & Transfer Size), RFC 959 (FTP), RFC 3164 / 5424 (Syslog).")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
            }
            .padding(24)
        }
    }
}
