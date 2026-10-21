import SwiftUI
import AppKit

public struct FTPServerView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedUsername: String = "anonymous"
    @State private var showingPasswordSheet = false
    @State private var newPasswordInput = ""
    
    public init() {}
    
    private var currentUserIndex: Int? {
        appState.ftpServerConfig.users.firstIndex(where: { $0.username == selectedUsername })
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FTP Server")
                        .font(.system(size: 20, weight: .bold))
                    Text("RFC 959 compliant FTP daemon with PASV/PORT, MD5 hashes, and per-user rights")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Text("Port:")
                            .font(.system(size: 12))
                        TextField("21", value: $appState.ftpServerConfig.port, formatter: NumberFormatter())
                            .frame(width: 60)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Button(action: {
                        appState.toggleFTPServer()
                    }) {
                        Label(
                            appState.isFTPServerRunning ? "Stop Server" : "Start Server",
                            systemImage: appState.isFTPServerRunning ? "stop.fill" : "play.fill"
                        )
                        .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(appState.isFTPServerRunning ? .red : .green)
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Main User Management & Connection Monitor
            HSplitView {
                // Left Column: User Profiles & Rights
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Configured User Profiles")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button("+ Add User") {
                            addNewUser()
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                        .font(.system(size: 12, weight: .medium))
                    }
                    
                    // User selection list
                    List(selection: $selectedUsername) {
                        ForEach(appState.ftpServerConfig.users) { user in
                            HStack {
                                Image(systemName: user.isAnonymous ? "person.crop.circle.badge.questionmark" : "person.crop.circle")
                                    .foregroundColor(user.canLogin ? .accentColor : .secondary)
                                Text(user.username)
                                    .font(.system(size: 13, weight: user.username == selectedUsername ? .bold : .regular))
                                Spacer()
                                if !user.canLogin {
                                    Text("Disabled")
                                        .font(.system(size: 10))
                                        .foregroundColor(.red)
                                }
                            }
                            .tag(user.username)
                        }
                    }
                    .frame(height: 120)
                    .listStyle(.inset)
                    
                    Divider()
                    
                    // User Details Form
                    if let idx = currentUserIndex {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Profile Name:")
                                    .font(.system(size: 12, weight: .medium))
                                    .frame(width: 100, alignment: .leading)
                                if appState.ftpServerConfig.users[idx].isAnonymous {
                                    Text("anonymous (built-in)")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.secondary)
                                } else {
                                    TextField("Username", text: $appState.ftpServerConfig.users[idx].username)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                            
                            HStack {
                                Text("Password:")
                                    .font(.system(size: 12, weight: .medium))
                                    .frame(width: 100, alignment: .leading)
                                if appState.ftpServerConfig.users[idx].isAnonymous {
                                    Text("No password required")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                } else {
                                    Button("Set / Change Password...") {
                                        newPasswordInput = ""
                                        showingPasswordSheet = true
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            
                            HStack {
                                Text("User Directory:")
                                    .font(.system(size: 12, weight: .medium))
                                    .frame(width: 100, alignment: .leading)
                                TextField("User root folder", text: $appState.ftpServerConfig.users[idx].userDirectory)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                                Button("Browse...") {
                                    selectUserFolder(userIndex: idx)
                                }
                            }
                            
                            Text("User Rights Checklist:")
                                .font(.system(size: 12, weight: .bold))
                                .padding(.top, 4)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                Toggle("Login", isOn: $appState.ftpServerConfig.users[idx].canLogin)
                                Toggle("Download", isOn: $appState.ftpServerConfig.users[idx].canDownload)
                                Toggle("Upload", isOn: $appState.ftpServerConfig.users[idx].canUpload)
                                Toggle("Overwrite Files", isOn: $appState.ftpServerConfig.users[idx].canOverwrite)
                                Toggle("Delete Files", isOn: $appState.ftpServerConfig.users[idx].canDelete)
                                Toggle("Rename Files", isOn: $appState.ftpServerConfig.users[idx].canRename)
                                Toggle("Make Directories", isOn: $appState.ftpServerConfig.users[idx].canMkdir)
                                Toggle("Delete Directories", isOn: $appState.ftpServerConfig.users[idx].canRmdir)
                            }
                            .font(.system(size: 11))
                            .toggleStyle(.checkbox)
                            
                            HStack {
                                Spacer()
                                if !appState.ftpServerConfig.users[idx].isAnonymous {
                                    Button("Delete Profile") {
                                        deleteUser(at: idx)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.red)
                                }
                            }
                            .padding(.top, 6)
                        }
                    }
                }
                .padding(14)
                .frame(minWidth: 380)
                
                // Right Column: Connected Sessions & Live Log
                VStack(spacing: 0) {
                    // Active Sessions
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Active FTP Sessions (\(appState.ftpSessions.count))")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.top, 10)
                        
                        if appState.ftpSessions.isEmpty {
                            Text("No active FTP client sessions.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                        } else {
                            List(appState.ftpSessions) { session in
                                HStack {
                                    Image(systemName: "desktopcomputer")
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("\(session.username) @ \(session.clientIP):\(session.clientPort)")
                                            .font(.system(size: 11, weight: .bold))
                                        Text("CWD: \(session.currentDirectory)")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text("Connected")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(.green)
                                }
                            }
                            .frame(height: 100)
                            .listStyle(.inset)
                        }
                    }
                    
                    Divider()
                    
                    // FTP Log Stream
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("FTP Command & Transfer Log")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Button("Clear") {
                                appState.ftpLogs.removeAll()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 3) {
                                    ForEach(Array(appState.ftpLogs.enumerated()), id: \.offset) { idx, line in
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
                            .onChange(of: appState.ftpLogs.count) { _ in
                                if let last = appState.ftpLogs.indices.last {
                                    proxy.scrollTo(last, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                .frame(minWidth: 320)
            }
        }
        .sheet(isPresented: $showingPasswordSheet) {
            VStack(spacing: 16) {
                Text("Set Password for \(selectedUsername)")
                    .font(.headline)
                
                SecureField("Enter new password", text: $newPasswordInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                
                HStack(spacing: 16) {
                    Button("Cancel") {
                        showingPasswordSheet = false
                    }
                    Button("Save Password") {
                        if let idx = currentUserIndex {
                            appState.ftpServerConfig.users[idx].passwordHash = FTPUser.hashMD5(newPasswordInput)
                        }
                        showingPasswordSheet = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
            .frame(width: 320)
        }
    }
    
    private func addNewUser() {
        let baseName = "user\(appState.ftpServerConfig.users.count)"
        let defaultPath = (FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.appendingPathComponent("SysTFTP/FTP/\(baseName)").path) ?? "/tmp/SysTFTP/FTP/\(baseName)"
        let newUser = FTPUser(
            username: baseName,
            password: "password123",
            userDirectory: defaultPath,
            canLogin: true,
            canUpload: true,
            canDownload: true,
            canOverwrite: true,
            canDelete: true,
            canRename: true,
            canMkdir: true,
            canRmdir: true,
            isAnonymous: false
        )
        appState.ftpServerConfig.users.append(newUser)
        selectedUsername = newUser.username
    }
    
    private func deleteUser(at index: Int) {
        guard !appState.ftpServerConfig.users[index].isAnonymous else { return }
        appState.ftpServerConfig.users.remove(at: index)
        selectedUsername = "anonymous"
    }
    
    private func selectUserFolder(userIndex: Int) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose User Root Folder"
        if panel.runModal() == .OK, let url = panel.url {
            appState.ftpServerConfig.users[userIndex].userDirectory = url.path
        }
    }
}
