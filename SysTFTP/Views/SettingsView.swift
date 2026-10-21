import SwiftUI

public struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showInMenuBar = true

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            PageHeaderView(title: "设置", subtitle: "端口预设、系统集成与应用信息") {
                EmptyView()
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    FormSectionView(title: "端口预设与权限") {
                        Text("低于 1024 的标准端口可能需要管理员权限。选择预设可同时设置 TFTP、FTP 和 Syslog 端口。")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                            portPreset(title: "标准端口", subtitle: "可能需要管理员权限", ports: [69, 21, 514])
                            portPreset(title: "普通端口", subtitle: "无需管理员权限", ports: [6969, 2121, 5140])
                        }
                    }

                    FormSectionView(title: "系统集成") {
                        Toggle("在 macOS 菜单栏显示 SysTFTP 图标", isOn: $showInMenuBar)
                        Divider()
                        Toggle("启动后最小化到菜单栏", isOn: .constant(false))
                        Divider()
                        Toggle("文件传输期间防止系统休眠", isOn: .constant(true))
                    }
                    .font(.system(size: 13))
                    .toggleStyle(.checkbox)

                    FormSectionView(title: "关于 SysTFTP") {
                        HStack(spacing: 14) {
                            Image(nsImage: NSImage(contentsOfFile: Bundle.main.path(forResource: "AppIcon", ofType: "icns") ?? "") ?? NSImage())
                                .resizable()
                                .frame(width: 48, height: 48)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("SysTFTP macOS 版")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("版本 1.0.0 · 构建 2026.10")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        Text("经典 3Com 3CDaemon 工具的现代 macOS 原生重制版，为网络工程师、IT 专业人员和嵌入式开发者提供常用网络服务。")
                        Text("支持标准：RFC 1350（TFTP）、RFC 2347（选项扩展）、RFC 2348（块大小）、RFC 2349（超时与传输大小）、RFC 959（FTP）、RFC 3164 / 5424（Syslog）。")
                            .foregroundColor(.secondary)
                    }
                    .font(.system(size: 13))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 900, alignment: .leading)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func portPreset(title: String, subtitle: String, ports: [Int]) -> some View {
        Button(action: {
            appState.tftpServerConfig.port = ports[0]
            appState.ftpServerConfig.port = ports[1]
            appState.syslogConfig.port = ports[2]
        }) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Divider()
                HStack(spacing: 12) {
                    ForEach(Array(zip(["TFTP", "FTP", "Syslog"], ports)), id: \.0) { name, port in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(name)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text(String(port))
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
    }
}
