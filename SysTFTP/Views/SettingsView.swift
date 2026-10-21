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
                    PortSettingsView(forwarding: appState.portForwarding)

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
                                Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版")")
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

}

struct PortSettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var forwarding: PortForwardingService
    @State private var feedback: String?
    @State private var feedbackIsError = false
    @State private var feedbackIsForwarding = false
    @State private var pendingAction: PendingAction?
    @State private var showsStopConfirmation = false

    private enum PendingAction {
        case preset(ServerPortPreset)
        case enableForwarding
    }

    var body: some View {
        VStack(spacing: 20) {
            FormSectionView(title: "端口预设与权限") {
                Text("点击下方“应用”按钮切换三个服务的监听端口。普通端口无需管理员权限；设备连接时也需填写对应端口。")
                    .foregroundColor(.secondary)
                Text("当前配置：TFTP \(String(appState.tftpServerConfig.port)) · FTP \(String(appState.ftpServerConfig.port)) · Syslog \(String(appState.syslogConfig.port))")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .textSelection(.enabled)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], spacing: 16) {
                    ForEach(ServerPortPreset.allCases) { preset in portPreset(preset) }
                }
                if !feedbackIsForwarding { feedbackBanner }
                Text("端口会自动保存。切换运行中的服务时，会先确认停止服务；应用后请重新启动服务。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            FormSectionView(title: "一键解决特权端口") {
                Label(forwardingStatus, systemImage: forwarding.status == .enabled ? "checkmark.shield.fill" : "shield")
                    .foregroundColor(forwarding.status == .enabled ? Color.green : Color.secondary)
                    .font(.system(size: 13, weight: .medium))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { forwardingButtons }
                    VStack(alignment: .leading, spacing: 12) { forwardingButtons }
                }
                Text("设备必须使用 69、21、514 等标准端口时，可启用系统转发。SysTFTP 会切换到普通端口运行，其他设备仍使用标准端口访问本机。")
                Text("UDP 69 → 6969　·　TCP 21 → 2121　·　UDP 514 → 5140")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .textSelection(.enabled)
                if forwarding.isBusy {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("正在等待管理员授权或处理端口转发…")
                    }
                }
                if feedbackIsForwarding { feedbackBanner }
                Text("系统会请求管理员授权。转发适用于其他设备发往本机的 IPv4 连接；本机测试请用普通端口。重启 macOS 后需重新启用，应用退出不会关闭转发。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .font(.system(size: 13))
        .lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)
        .alert("停止服务后继续？", isPresented: $showsStopConfirmation) {
            Button("停止服务并继续", role: .destructive) {
                guard let action = pendingAction else { return }
                pendingAction = nil
                switch action {
                case .preset(let preset):
                    appState.stopAllServices()
                    apply(preset, stoppedServices: true)
                case .enableForwarding:
                    performForwarding(.enable, mayStopServices: true)
                }
            }
            Button("取消", role: .cancel) { pendingAction = nil }
        } message: {
            Text("当前有服务正在运行，继续会中断现有连接和文件传输。端口应用后，需重新启动服务。管理员授权取消时不会停止服务。")
        }
    }

    @ViewBuilder
    private var feedbackBanner: some View {
        if let feedback {
            Label(feedback, systemImage: feedbackIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundColor(feedbackIsError ? Color.red : Color.green)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background((feedbackIsError ? Color.red : Color.green).opacity(0.08))
                .cornerRadius(8)
                .accessibilityIdentifier("port-settings-feedback")
        }
    }

    @ViewBuilder
    private var forwardingButtons: some View {
        Button(forwarding.status == .enabled ? "重新应用端口转发…" : "一键解决特权端口…") {
            if appState.hasRunningServices {
                pendingAction = .enableForwarding
                showsStopConfirmation = true
            } else {
                performForwarding(.enable)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(forwarding.isBusy)
        Button("检查转发状态…") { performForwarding(.status) }
            .disabled(forwarding.isBusy)
        Button("关闭转发…") { performForwarding(.disable) }
            .disabled(forwarding.isBusy || forwarding.status == .disabled)
    }

    private var forwardingStatus: String {
        switch forwarding.status {
        case .unknown: return "转发状态尚未检查"
        case .enabled:
            return appState.currentPortPreset == .unprivileged
                ? "标准端口转发已启用"
                : "转发已启用；请将应用切换到普通端口"
        case .disabled: return "标准端口转发未启用"
        }
    }

    private func portPreset(_ preset: ServerPortPreset) -> some View {
        let selected = appState.currentPortPreset == preset
        return Button {
            feedbackIsForwarding = false
            if preset == .standard && forwarding.status == .enabled {
                report("请先关闭端口转发，再应用标准端口，避免转发目标与监听端口不一致。", isError: true)
            } else if selected {
                report("当前已使用\(preset.title)：\(preset.summary)。")
            } else if appState.hasRunningServices {
                pendingAction = .preset(preset)
                showsStopConfirmation = true
            } else {
                apply(preset)
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(preset.title).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    if selected {
                        Label("当前使用", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.accentColor)
                    }
                }
                Text(preset == .standard ? "低端口可能需要管理员权限" : "推荐使用，无需管理员权限")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Divider()
                HStack(spacing: 12) {
                    ForEach(Array(zip(["TFTP", "FTP", "Syslog"], preset.ports)), id: \.0) { name, port in
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
                Label(selected ? "已应用" : "应用\(preset.title)", systemImage: selected ? "checkmark" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.10))
                    .cornerRadius(6)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.accentColor.opacity(0.05) : Color(NSColor.textBackgroundColor))
            .cornerRadius(9)
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(forwarding.isBusy)
        .help("应用后会同时更新 TFTP、FTP 和 Syslog 端口")
        .accessibilityIdentifier("port-preset-\(preset.rawValue)")
    }

    private func apply(_ preset: ServerPortPreset, stoppedServices: Bool = false) {
        guard appState.applyPortPreset(preset) else {
            report("请先停止运行中的服务，再切换端口。", isError: true)
            return
        }
        let hint = preset == .unprivileged
            ? "连接设备时请使用上述普通端口；如需继续使用标准端口，可启用下方的系统转发。"
            : "若服务提示权限不足，请使用普通端口，或启用下方的系统转发。"
        report("\(stoppedServices ? "已停止服务，" : "")已应用\(preset.title)：\(preset.summary)。配置已保存，请启动需要的服务。\(hint)")
    }

    private func performForwarding(_ action: PortForwardingService.Action, mayStopServices: Bool = false) {
        feedback = nil
        feedbackIsForwarding = true
        Task {
            do {
                let status = try await forwarding.perform(action)
                if action == .enable {
                    if appState.hasRunningServices && !mayStopServices {
                        report("转发已启用。请停止服务后应用普通端口，再重新启动服务。", isError: true)
                        return
                    }
                    if mayStopServices { appState.stopAllServices() }
                    guard appState.applyPortPreset(.unprivileged) else { return }
                    report("标准端口转发已启用，应用已切换到 6969 / 2121 / 5140。请启动需要的服务，其他设备可继续使用 69 / 21 / 514 访问本机。")
                } else if status == .enabled {
                    report("已确认标准端口转发正在运行，转发目标为 6969 / 2121 / 5140。")
                } else {
                    report("标准端口转发未启用。使用普通端口时，连接设备需填写 6969 / 2121 / 5140；应用的当前端口配置保持不变。")
                }
            } catch {
                report(error.localizedDescription, isError: true)
            }
        }
    }

    private func report(_ message: String, isError: Bool = false) {
        feedback = message
        feedbackIsError = isError
        appState.appendGeneralLog(message)
    }
}
