import Foundation
import Combine

@MainActor
public final class PortForwardingService: ObservableObject {
    public enum Action: String, Sendable {
        case enable, disable, status
    }

    public enum Status: Sendable {
        case unknown, enabled, disabled
    }

    @Published public private(set) var status: Status = .unknown
    @Published public private(set) var isBusy = false

    public init() {}

    @discardableResult
    public func perform(_ action: Action) async throws -> Status {
        guard !isBusy else {
            throw failure("正在处理端口转发，请稍候。")
        }
        #if SWIFT_PACKAGE
        let resourceBundle = Bundle.module
        #else
        let resourceBundle = Bundle.main
        #endif
        guard let helper = resourceBundle.url(forResource: "port_forwarding", withExtension: "sh") else {
            throw failure("安装包缺少端口转发组件，请重新安装 SysTFTP。")
        }

        isBusy = true
        defer { isBusy = false }
        let command = "/bin/sh \(Self.shellQuote(helper.path)) \(action.rawValue)"
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        let script = "do shell script \"\(escaped)\" with administrator privileges\n"
        do {
            // osascript owns the authorization dialog; its wait never blocks SwiftUI.
            let output = try await Task.detached(priority: .userInitiated) {
                let process = Process()
                let input = Pipe()
                let output = Pipe()
                let errors = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-"]
                process.standardInput = input
                process.standardOutput = output
                process.standardError = errors
                try process.run()
                try input.fileHandleForWriting.write(contentsOf: Data(script.utf8))
                try input.fileHandleForWriting.close()
                let response = output.fileHandleForReading.readDataToEndOfFile()
                let diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    let message = String(decoding: diagnostics, as: UTF8.self)
                    throw NSError(domain: "SysTFTP.PortForwarding", code: Int(process.terminationStatus),
                                  userInfo: [NSLocalizedDescriptionKey: Self.failureDescription(message)])
                }
                return String(decoding: response, as: UTF8.self)
            }.value
            if output.contains("SYSTFTP_PF_ENABLED") {
                status = .enabled
            } else if output.contains("SYSTFTP_PF_DISABLED") {
                status = .disabled
            } else {
                throw failure("未能确认端口转发状态，请检查后重试。")
            }
            return status
        } catch {
            status = .unknown
            throw error
        }
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    nonisolated static func failureDescription(_ diagnostics: String) -> String {
        if diagnostics.contains("(-128)") {
            return "已取消管理员授权，未应用此次操作。"
        }
        // These pfctl notices are informational; keep actual errors in the UI.
        let notices: Set<String> = [
            "No ALTQ support in kernel",
            "ALTQ related functions disabled",
            "pfctl: Use of -f option, could result in flushing of rules",
            "present in the main ruleset added by the system at startup.",
            "See /etc/pf.conf for further details."
        ]
        let message = diagnostics
            .replacingOccurrences(of: #"^\d+:\d+: execution error: "#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\(-?\d+\)\s*$"#, with: "", options: .regularExpression)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !notices.contains($0) }
            .joined(separator: "\n")
        return "端口转发操作失败：\(message.isEmpty ? "请检查系统防火墙配置后重试。" : message)"
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "SysTFTP.PortForwarding", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
