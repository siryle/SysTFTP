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
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            SidebarCommands()
            
            CommandMenu("Services") {
                Button(appState.isTFTPServerRunning ? "Stop TFTP Server" : "Start TFTP Server") {
                    appState.toggleTFTPServer()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                
                Button(appState.isFTPServerRunning ? "Stop FTP Server" : "Start FTP Server") {
                    appState.toggleFTPServer()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                
                Button(appState.isSyslogServerRunning ? "Stop Syslog Server" : "Start Syslog Server") {
                    appState.toggleSyslogServer()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Start All Services") {
                    appState.startAllServices()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                
                Button("Stop All Services") {
                    appState.stopAllServices()
                }
            }
        }
        
        #if os(macOS)
        MenuBarExtra("SysTFTP", systemImage: menuBarIcon) {
            Text("SysTFTP Suite")
                .font(.headline)
            
            Divider()
            
            Button(action: { appState.toggleTFTPServer() }) {
                HStack {
                    Text("TFTP Server (\(appState.tftpServerConfig.port))")
                    Spacer()
                    Text(appState.isTFTPServerRunning ? "Running" : "Stopped")
                }
            }
            
            Button(action: { appState.toggleFTPServer() }) {
                HStack {
                    Text("FTP Server (\(appState.ftpServerConfig.port))")
                    Spacer()
                    Text(appState.isFTPServerRunning ? "Running" : "Stopped")
                }
            }
            
            Button(action: { appState.toggleSyslogServer() }) {
                HStack {
                    Text("Syslog Server (\(appState.syslogConfig.port))")
                    Spacer()
                    Text(appState.isSyslogServerRunning ? "Running" : "Stopped")
                }
            }
            
            Divider()
            
            Button("Open SysTFTP Dashboard") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            
            Divider()
            
            Button("Quit SysTFTP") {
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
