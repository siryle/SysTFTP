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
            PageHeaderView(
                title: "FTP 服务器",
                subtitle: "RFC 959 · PASV/PORT、MD5 密码与用户权限管理"
            ) {
                HStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Text("TCP 端口")
                            .font(.system(size: 12))
                        TextField("21", value: $appState.ftpServerConfig.port, formatter: NumberFormatter())
                            .frame(width: 76)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button(action: { appState.toggleFTPServer() }) {
                        Label(
                            appState.isFTPServerRunning ? "停止服务" : "启动服务",
                            systemImage: appState.isFTPServerRunning ? "stop.fill" : "play.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(appState.isFTPServerRunning ? .red : .green)
                }
            }

            Divider()

            HSplitView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        userList
                        if let index = currentUserIndex {
                            userDetails(at: index)
                        }
                    }
                    .padding(20)
                }
                .frame(minWidth: 320, idealWidth: 380)

                VStack(spacing: 0) {
                    sessionList
                    Divider()
                    ConsoleLogView(title: "FTP 命令与传输日志", lines: appState.ftpLogs) {
                        appState.ftpLogs.removeAll()
                    }
                    .frame(minHeight: 160)
                }
                .frame(minWidth: 280)
            }
        }
        .sheet(isPresented: $showingPasswordSheet) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("设置用户密码")
                        .font(.system(size: 18, weight: .semibold))
                    Text(selectedUsername)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                SecureField("输入新密码", text: $newPasswordInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(savePassword)
                HStack(spacing: 12) {
                    Spacer()
                    Button("取消") { showingPasswordSheet = false }
                        .keyboardShortcut(.cancelAction)
                    Button("保存密码", action: savePassword)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 380)
        }
    }

    private var userList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("用户列表")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: addNewUser) {
                    Label("添加用户", systemImage: "plus")
                }
                .controlSize(.small)
            }
            List(selection: $selectedUsername) {
                ForEach(appState.ftpServerConfig.users) { user in
                    HStack(spacing: 10) {
                        Image(systemName: user.isAnonymous ? "person.crop.circle.badge.questionmark" : "person.crop.circle")
                            .foregroundColor(user.canLogin ? .accentColor : .secondary)
                        Text(user.username)
                            .font(.system(size: 13, weight: user.username == selectedUsername ? .semibold : .regular))
                            .lineLimit(1)
                            .help(user.username)
                        Spacer()
                        if !user.canLogin {
                            Text("已禁用")
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.vertical, 4)
                    .tag(user.username)
                }
            }
            .frame(height: 128)
            .listStyle(.inset)
            .cornerRadius(8)
        }
    }

    private func userDetails(at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            FormSectionView(title: "账户信息") {
                FormFieldView(title: "用户名") {
                    if appState.ftpServerConfig.users[index].isAnonymous {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("anonymous")
                                .font(.system(size: 13, weight: .medium))
                            Text("内置匿名用户，无需密码")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        TextField("用户名", text: $appState.ftpServerConfig.users[index].username)
                    }
                }
                if !appState.ftpServerConfig.users[index].isAnonymous {
                    FormFieldView(title: "登录密码") {
                        Button("设置 / 修改密码…") {
                            newPasswordInput = ""
                            showingPasswordSheet = true
                        }
                    }
                }
                FormFieldView(title: "用户根目录") {
                    TextField("用户根目录", text: $appState.ftpServerConfig.users[index].userDirectory)
                        .font(.system(size: 12, design: .monospaced))
                        .help(appState.ftpServerConfig.users[index].userDirectory)
                    Button("选择目录…") { selectUserFolder(userIndex: index) }
                        .controlSize(.small)
                }
            }
            .textFieldStyle(.roundedBorder)

            FormSectionView(title: "访问权限") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 16)], alignment: .leading, spacing: 14) {
                    Toggle("允许登录", isOn: $appState.ftpServerConfig.users[index].canLogin)
                    Toggle("下载文件", isOn: $appState.ftpServerConfig.users[index].canDownload)
                    Toggle("上传文件", isOn: $appState.ftpServerConfig.users[index].canUpload)
                    Toggle("覆盖文件", isOn: $appState.ftpServerConfig.users[index].canOverwrite)
                    Toggle("删除文件", isOn: $appState.ftpServerConfig.users[index].canDelete)
                    Toggle("重命名文件", isOn: $appState.ftpServerConfig.users[index].canRename)
                    Toggle("创建目录", isOn: $appState.ftpServerConfig.users[index].canMkdir)
                    Toggle("删除目录", isOn: $appState.ftpServerConfig.users[index].canRmdir)
                }
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
            }

            if !appState.ftpServerConfig.users[index].isAnonymous {
                HStack {
                    Spacer()
                    Button("删除用户", role: .destructive) { deleteUser(at: index) }
                }
            }
        }
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("在线会话（\(appState.ftpSessions.count)）")
                .font(.system(size: 13, weight: .semibold))
            if appState.ftpSessions.isEmpty {
                Label("暂无客户端连接", systemImage: "desktopcomputer")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(appState.ftpSessions) { session in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(session.username)
                                    .font(.system(size: 13, weight: .semibold))
                                Text("\(session.clientIP):\(String(session.clientPort))")
                                    .font(.system(size: 12, design: .monospaced))
                                Text("当前目录：\(session.currentDirectory)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .help(session.currentDirectory)
                            }
                            .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 150)
            }
        }
        .padding(16)
    }

    private func savePassword() {
        if let index = currentUserIndex {
            appState.ftpServerConfig.users[index].passwordHash = FTPUser.hashMD5(newPasswordInput)
        }
        showingPasswordSheet = false
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
        panel.title = "选择用户根目录"
        panel.prompt = "选择目录"
        if panel.runModal() == .OK, let url = panel.url {
            appState.ftpServerConfig.users[userIndex].userDirectory = url.path
        }
    }
}
