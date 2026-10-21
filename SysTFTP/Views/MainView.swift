import SwiftUI

public struct MainView: View {
    @EnvironmentObject var appState: AppState
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView {
            List(AppNavigationItem.allCases, selection: $appState.selectedItem) { item in
                NavigationLink(value: item) {
                    HStack(spacing: 10) {
                        Image(systemName: item.icon)
                            .font(.system(size: 15))
                            .foregroundColor(iconColor(for: item))
                            .frame(width: 22)
                        
                        Text(item.rawValue)
                            .font(.system(size: 13, weight: .medium))
                        
                        Spacer()
                        
                        // Active status indicators in sidebar
                        if item == .tftpServer && appState.isTFTPServerRunning {
                            Circle().fill(Color.green).frame(width: 7, height: 7)
                        } else if item == .ftpServer && appState.isFTPServerRunning {
                            Circle().fill(Color.green).frame(width: 7, height: 7)
                        } else if item == .syslogServer && appState.isSyslogServerRunning {
                            Circle().fill(Color.green).frame(width: 7, height: 7)
                        } else if item == .tftpClient && appState.isClientTransferring {
                            Circle().fill(Color.blue).frame(width: 7, height: 7)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
            .navigationTitle("SysTFTP")
            .listStyle(.sidebar)
            .frame(minWidth: 190, idealWidth: 210)
        } detail: {
            Group {
                switch appState.selectedItem {
                case .overview:
                    OverviewView()
                case .tftpServer:
                    TFTPServerView()
                case .tftpClient:
                    TFTPClientView()
                case .ftpServer:
                    FTPServerView()
                case .syslogServer:
                    SyslogServerView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(minWidth: 700, minHeight: 520)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    NetworkBadgeView()
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        let anyRunning = appState.isTFTPServerRunning || appState.isFTPServerRunning || appState.isSyslogServerRunning
                        if anyRunning {
                            appState.stopAllServices()
                        } else {
                            appState.startAllServices()
                        }
                    }) {
                        let anyRunning = appState.isTFTPServerRunning || appState.isFTPServerRunning || appState.isSyslogServerRunning
                        Label(anyRunning ? "Stop All Daemons" : "Start All Daemons", systemImage: anyRunning ? "stop.circle.fill" : "play.circle.fill")
                            .foregroundColor(anyRunning ? .red : .green)
                    }
                    .help("Quick toggle for TFTP, FTP and Syslog servers")
                }
            }
        }
    }
    
    private func iconColor(for item: AppNavigationItem) -> Color {
        switch item {
        case .overview: return .indigo
        case .tftpServer: return .blue
        case .tftpClient: return .cyan
        case .ftpServer: return .teal
        case .syslogServer: return .purple
        case .settings: return .gray
        }
    }
}
