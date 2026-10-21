import SwiftUI
import AppKit

public struct SyslogServerView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var selectedSeverity: SyslogSeverity? = nil
    @State private var selectedFacility: SyslogFacility? = nil
    @State private var filterIP = ""
    @State private var isAutoScrollPaused = false
    @State private var selectedLogId: UUID? = nil
    
    public init() {}
    
    private var filteredMessages: [SyslogMessage] {
        appState.syslogMessages.filter { msg in
            if !searchText.isEmpty {
                let term = searchText.lowercased()
                let matches = msg.message.lowercased().contains(term) ||
                              msg.sourceIP.contains(term) ||
                              msg.tag.lowercased().contains(term) ||
                              msg.hostname.lowercased().contains(term)
                if !matches { return false }
            }
            if let sev = selectedSeverity, msg.severity > sev {
                return false
            }
            if let fac = selectedFacility, msg.facility != fac {
                return false
            }
            if !filterIP.isEmpty && !msg.sourceIP.contains(filterIP) {
                return false
            }
            return true
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            PageHeaderView(
                title: "Syslog 日志服务器",
                subtitle: "RFC 3164 / 5424 · 实时接收与查看设备日志"
            ) {
                HStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Text("UDP 端口")
                            .font(.system(size: 12))
                        TextField("514", value: $appState.syslogConfig.port, formatter: NumberFormatter())
                            .frame(width: 76)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button(action: { appState.toggleSyslogServer() }) {
                        Label(
                            appState.isSyslogServerRunning ? "停止服务" : "启动服务",
                            systemImage: appState.isSyslogServerRunning ? "stop.fill" : "play.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(appState.isSyslogServerRunning ? .red : .green)
                }
            }

            Divider()
            filters
            Divider()

            if filteredMessages.isEmpty {
                emptyState
            } else {
                GeometryReader { geometry in
                    if geometry.size.width < 800 {
                        messageList(compact: true)
                    } else {
                        ScrollView(.horizontal) {
                            VStack(spacing: 0) {
                                tableHeader
                                Divider()
                                messageList(compact: false)
                            }
                            .frame(width: max(geometry.size.width, 900), height: geometry.size.height)
                        }
                    }
                }
            }

            Divider()
            VStack(alignment: .leading, spacing: 5) {
                Text("事件总数：\(appState.syslogMessages.count)　当前显示：\(filteredMessages.count)")
                if appState.syslogConfig.saveToFile {
                    Text("保存位置：\(appState.syslogConfig.logDirectory)")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(appState.syslogConfig.logDirectory)
                }
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))
        }
    }

    private var filters: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索消息、主机或标签", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(7)
                .frame(maxWidth: .infinity)

                HStack(spacing: 8) {
                    Button(action: { isAutoScrollPaused.toggle() }) {
                        Label(isAutoScrollPaused ? "继续" : "暂停", systemImage: isAutoScrollPaused ? "play.circle" : "pause.circle")
                    }
                    Button("清空") { appState.clearSyslogs() }
                    Button("导出…") { exportSyslogs() }
                }
                .fixedSize()
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], alignment: .leading, spacing: 12) {
                FormFieldView(title: "严重级别") {
                    Picker("严重级别", selection: $selectedSeverity) {
                        Text("全部级别").tag(SyslogSeverity?.none)
                        Divider()
                        ForEach(SyslogSeverity.allCases) { severity in
                            Text("≤ \(severity.displayName)").tag(SyslogSeverity?.some(severity))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                FormFieldView(title: "日志来源") {
                    Picker("日志来源", selection: $selectedFacility) {
                        Text("全部来源").tag(SyslogFacility?.none)
                        Divider()
                        ForEach(SyslogFacility.allCases) { facility in
                            Text(facility.displayName).tag(SyslogFacility?.some(facility))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                FormFieldView(title: "来源 IP") {
                    TextField("输入完整或部分 IP", text: $filterIP)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var tableHeader: some View {
        HStack(spacing: 12) {
            Text("时间").frame(width: 146, alignment: .leading)
            Text("来源 IP").frame(width: 120, alignment: .leading)
            Text("日志来源").frame(width: 104, alignment: .leading)
            Text("严重级别").frame(width: 88, alignment: .leading)
            Text("标签 / 进程").frame(width: 110, alignment: .leading)
            Text("消息").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.secondary)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.5))
            Text(appState.isSyslogServerRunning ? "正在监听 UDP \(appState.syslogConfig.port)，暂无匹配的日志事件。" : "Syslog 日志服务器已停止。")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func messageList(compact: Bool) -> some View {
        ScrollViewReader { proxy in
            List(filteredMessages, selection: $selectedLogId) { message in
                Group {
                    if compact {
                        compactMessageRow(message)
                    } else {
                        messageRow(message)
                    }
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                .tag(message.id)
                .id(message.id)
            }
            .listStyle(.plain)
            .onChange(of: appState.syslogMessages.first?.id) { id in
                if !isAutoScrollPaused, let id = id {
                    proxy.scrollTo(id, anchor: .top)
                }
            }
        }
    }

    private func compactMessageRow(_ message: SyslogMessage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(message.sourceIP)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                Spacer()
                Text(message.formattedTimestamp)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 10) {
                severityBadge(message.severity)
                Text(message.facility.displayName)
                    .foregroundColor(.secondary)
                    .fixedSize()
                if !message.tag.isEmpty {
                    Text(message.tag)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .help(message.tag)
                }
            }
            .font(.system(size: 12))
            Text(message.message)
                .font(.system(size: 13))
                .lineSpacing(4)
                .lineLimit(3)
                .textSelection(.enabled)
                .help(message.message)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }

    private func severityBadge(_ severity: SyslogSeverity) -> some View {
        Text(severity.displayName)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(severity.color.opacity(0.15))
            .foregroundColor(severity.color)
            .cornerRadius(5)
            .fixedSize()
    }

    private func messageRow(_ message: SyslogMessage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(message.formattedTimestamp)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 146, alignment: .leading)
            Text(message.sourceIP)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 120, alignment: .leading)
            Text(message.facility.displayName)
                .foregroundColor(.secondary)
                .frame(width: 104, alignment: .leading)
            HStack {
                severityBadge(message.severity)
            }
            .frame(width: 88, alignment: .leading)
            Text(message.tag.isEmpty ? "—" : message.tag)
                .frame(width: 110, alignment: .leading)
                .lineLimit(1)
                .help(message.tag)
            Text(message.message)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
                .textSelection(.enabled)
                .help(message.message)
        }
        .font(.system(size: 12))
    }

    private func exportSyslogs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "syslog_export_\(Int(Date().timeIntervalSince1970)).csv"
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        if panel.runModal() == .OK, let url = panel.url {
            var csv = "Timestamp,SourceIP,Facility,Severity,Tag,Message\n"
            for msg in filteredMessages {
                let cleanMsg = msg.message.replacingOccurrences(of: "\"", with: "\"\"")
                csv += "\"\(msg.formattedTimestamp)\",\"\(msg.sourceIP)\",\"\(msg.facility.name)\",\"\(msg.severity.name)\",\"\(msg.tag)\",\"\(cleanMsg)\"\n"
            }
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
