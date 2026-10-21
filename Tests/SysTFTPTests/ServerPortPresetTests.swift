import XCTest
@testable import SysTFTP

final class ServerPortPresetTests: XCTestCase {
    @MainActor
    func testPresetPersistsAndRestoresPorts() async {
        let name = "SysTFTPTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let state = AppState(defaults: defaults)
        XCTAssertTrue(state.applyPortPreset(.unprivileged))
        XCTAssertEqual(state.currentPortPreset, .unprivileged)
        let restored = AppState(defaults: defaults)
        XCTAssertEqual(restored.tftpServerConfig.port, 6969)
        XCTAssertEqual(restored.ftpServerConfig.port, 2121)
        XCTAssertEqual(restored.syslogConfig.port, 5140)
    }

    @MainActor
    func testRunningServicesMustStopBeforeApplyingPreset() async {
        let name = "SysTFTPTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let state = AppState(defaults: defaults)
        state.isSyslogServerRunning = true
        XCTAssertFalse(state.applyPortPreset(.unprivileged))
        XCTAssertEqual(state.currentPortPreset, .standard)
        state.stopAllServices()
        XCTAssertFalse(state.hasRunningServices)
        XCTAssertTrue(state.applyPortPreset(.unprivileged))
    }

    @MainActor
    func testInvalidSavedPortsFallBackToDefaultsAndCustomPortsRemainEditable() async {
        let name = "SysTFTPTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(-1, forKey: "ports.tftp")
        defaults.set(65536, forKey: "ports.ftp")
        let state = AppState(defaults: defaults)
        XCTAssertEqual(state.currentPortPreset, .standard)
        state.tftpServerConfig.port = 1069
        XCTAssertNil(state.currentPortPreset)
        XCTAssertEqual(AppState(defaults: defaults).tftpServerConfig.port, 1069)
    }

    @MainActor
    func testPrivilegedCommandQuotesApostrophesInAppPath() async {
        XCTAssertEqual(PortForwardingService.shellQuote("/Applications/Sean's App.app"),
                       "'/Applications/Sean'\\''s App.app'")
    }
}
