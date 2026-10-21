import SwiftUI
import AppKit

@main
public struct SysTFTPApp: App {
    @StateObject private var appState = AppState.shared
    
    public init() {}
    
    public var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appState)
                .frame(minWidth: 920, minHeight: 620)
        }
        .defaultSize(width: 1180, height: 820)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            SidebarCommands()
            
            CommandMenu("服务") {
                Button(appState.isTFTPServerRunning ? "停止 TFTP 服务" : "启动 TFTP 服务") {
                    appState.toggleTFTPServer()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                
                Button(appState.isFTPServerRunning ? "停止 FTP 服务" : "启动 FTP 服务") {
                    appState.toggleFTPServer()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                
                Button(appState.isSyslogServerRunning ? "停止 Syslog 服务" : "启动 Syslog 服务") {
                    appState.toggleSyslogServer()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                
                Divider()
                
                Button("启动全部服务") {
                    appState.startAllServices()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                
                Button("停止全部服务") {
                    appState.stopAllServices()
                }
            }
        }
        
        #if os(macOS)
        MenuBarExtra("SysTFTP", systemImage: menuBarIcon) {
            Text("SysTFTP 工具套件")
                .font(.headline)
            
            Divider()
            
            Button(action: { appState.toggleTFTPServer() }) {
                HStack {
                    Text("TFTP 服务器（\(appState.tftpServerConfig.port)）")
                    Spacer()
                    Text(appState.isTFTPServerRunning ? "运行中" : "已停止")
                }
            }
            
            Button(action: { appState.toggleFTPServer() }) {
                HStack {
                    Text("FTP 服务器（\(appState.ftpServerConfig.port)）")
                    Spacer()
                    Text(appState.isFTPServerRunning ? "运行中" : "已停止")
                }
            }
            
            Button(action: { appState.toggleSyslogServer() }) {
                HStack {
                    Text("Syslog 日志服务器（\(appState.syslogConfig.port)）")
                    Spacer()
                    Text(appState.isSyslogServerRunning ? "运行中" : "已停止")
                }
            }
            
            Divider()
            
            Button("打开 SysTFTP 控制台") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            
            Divider()
            
            Button("退出 SysTFTP") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        #endif
    }
    
    private var menuBarIcon: String {
        let count = (appState.isTFTPServerRunning ? 1 : 0) + (appState.isFTPServerRunning ? 1 : 0) + (appState.isSyslogServerRunning ? 1 : 0)
        return count > 0 ? "network.badge.shield.half.filled" : "network"
    }
}
