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
            // Header & Control Bar
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Syslog Server")
                            .font(.system(size: 20, weight: .bold))
                        Text("RFC 3164 / 5424 BSD-unix daemon on UDP port \(appState.syslogConfig.port)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 16) {
                        HStack(spacing: 6) {
                            Text("UDP Port:")
                                .font(.system(size: 12))
                            TextField("514", value: $appState.syslogConfig.port, formatter: NumberFormatter())
                                .frame(width: 60)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        Button(action: {
                            appState.toggleSyslogServer()
                        }) {
                            Label(
                                appState.isSyslogServerRunning ? "Stop Daemon" : "Start Daemon",
                                systemImage: appState.isSyslogServerRunning ? "stop.fill" : "play.fill"
                            )
                            .font(.system(size: 13, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(appState.isSyslogServerRunning ? .red : .green)
                    }
                }
                
                Divider()
                
                // Filters Toolbar
                HStack(spacing: 12) {
                    // Search bar
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search message, host, tag...", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    .frame(maxWidth: 240)
                    
                    // Severity Filter
                    Picker("Severity:", selection: $selectedSeverity) {
                        Text("All Severities").tag(SyslogSeverity?.none)
                        Divider()
                        ForEach(SyslogSeverity.allCases) { sev in
                            Text("≤ \(sev.name)").tag(SyslogSeverity?.some(sev))
                        }
                    }
                    .frame(width: 170)
                    
                    // Facility Filter
                    Picker("Facility:", selection: $selectedFacility) {
                        Text("All Facilities").tag(SyslogFacility?.none)
                        Divider()
                        ForEach(SyslogFacility.allCases) { fac in
                            Text(fac.name).tag(SyslogFacility?.some(fac))
                        }
                    }
                    .frame(width: 160)
                    
                    // IP filter
                    TextField("Filter IP...", text: $filterIP)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                        .font(.system(size: 11, design: .monospaced))
                    
                    Spacer()
                    
                    // Actions
                    Button(action: { isAutoScrollPaused.toggle() }) {
                        Label(isAutoScrollPaused ? "Resume" : "Pause", systemImage: isAutoScrollPaused ? "play.circle" : "pause.circle")
                            .font(.system(size: 11))
                    }
                    
                    Button("Clear") {
                        appState.clearSyslogs()
                    }
                    .font(.system(size: 11))
                    
                    Button("Export...") {
                        exportSyslogs()
                    }
                    .font(.system(size: 11))
                }
                .font(.system(size: 12))
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Syslog Table
            VStack(spacing: 0) {
                // Table Column Header
                HStack(spacing: 0) {
                    Text("Timestamp")
                        .frame(width: 140, alignment: .leading)
                    Text("Source IP")
                        .frame(width: 120, alignment: .leading)
                    Text("Facility")
                        .frame(width: 90, alignment: .leading)
                    Text("Severity")
                        .frame(width: 100, alignment: .leading)
                    Text("Tag / Process")
                        .frame(width: 110, alignment: .leading)
                    Text("Message")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor))
                
                Divider()
                
                if filteredMessages.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text(appState.isSyslogServerRunning ? "Listening on UDP 514... No matching syslog events received." : "Syslog Server is stopped.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredMessages, selection: $selectedLogId) { msg in
                        HStack(spacing: 0) {
                            Text(msg.formattedTimestamp)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 140, alignment: .leading)
                                .foregroundColor(.secondary)
                            
                            Text(msg.sourceIP)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .frame(width: 120, alignment: .leading)
                            
                            Text(msg.facility.name)
                                .font(.system(size: 11))
                                .frame(width: 90, alignment: .leading)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Text(msg.severity.name)
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(msg.severity.color.opacity(0.18))
                                    .foregroundColor(msg.severity.color)
                                    .cornerRadius(4)
                            }
                            .frame(width: 100, alignment: .leading)
                            
                            Text(msg.tag.isEmpty ? "-" : msg.tag)
                                .font(.system(size: 11, weight: .medium))
                                .frame(width: 110, alignment: .leading)
                                .lineLimit(1)
                            
                            Text(msg.message)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 3)
                        .tag(msg.id)
                    }
                    .listStyle(.inset)
                }
            }
            
            // Footer summary
            HStack {
                Text("Total events: \(appState.syslogMessages.count) | Showing: \(filteredMessages.count)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                if appState.syslogConfig.saveToFile {
                    Text("Logging to: \(appState.syslogConfig.logDirectory)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor))
        }
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
