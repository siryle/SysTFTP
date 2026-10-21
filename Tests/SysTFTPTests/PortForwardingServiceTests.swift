import XCTest
@testable import SysTFTP

final class PortForwardingServiceTests: XCTestCase {
    func testHarmlessPFNoticesDoNotHideActualFailure() {
        let diagnostics = """
        0:156: execution error: No ALTQ support in kernel
        ALTQ related functions disabled
        pfctl: Use of -f option, could result in flushing of rules
        present in the main ruleset added by the system at startup.
        See /etc/pf.conf for further details.

        No ALTQ support in kernel
        ALTQ related functions disabled
        未能验证转发规则，已回滚此次操作。 (1)
        """
        XCTAssertEqual(PortForwardingService.failureDescription(diagnostics),
                       "端口转发操作失败：未能验证转发规则，已回滚此次操作。")
    }

    func testRealPFDiagnosticsArePreserved() {
        XCTAssertEqual(PortForwardingService.failureDescription(
            "0:156: execution error: pfctl: /dev/pf: Permission denied (1)\n"),
            "端口转发操作失败：pfctl: /dev/pf: Permission denied")
    }

    func testAuthorizationCancellationIsExplained() {
        XCTAssertEqual(PortForwardingService.failureDescription(
            "0:156: execution error: User canceled. (-128)\n"),
            "已取消管理员授权，未应用此次操作。")
    }

    func testEmptyDiagnosticsHaveAnActionableFallback() {
        XCTAssertEqual(PortForwardingService.failureDescription(""),
                       "端口转发操作失败：请检查系统防火墙配置后重试。")
    }
}
