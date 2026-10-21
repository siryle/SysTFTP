import XCTest
@testable import SysTFTP

final class SysTFTPTests: XCTestCase {
    func testMD5Hashing() {
        let password = "admin"
        let hash = FTPUser.hashMD5(password)
        // MD5 of "admin" is 21232F297A57A5A743894A0E4A801FC3
        XCTAssertEqual(hash.uppercased(), "21232F297A57A5A743894A0E4A801FC3")
    }
    
    func testFTPUserVerification() {
        let user = FTPUser(username: "admin", password: "secretpassword", userDirectory: "/tmp")
        XCTAssertTrue(user.verifyPassword("secretpassword"))
        XCTAssertFalse(user.verifyPassword("wrongpassword"))
    }
    
    func testAnonymousUser() {
        let anon = FTPUser(username: "anonymous", password: "", userDirectory: "/tmp", isAnonymous: true)
        XCTAssertTrue(anon.verifyPassword("user@example.com"))
        XCTAssertTrue(anon.verifyPassword(""))
    }
    
    func testSyslogSeverity() {
        XCTAssertTrue(SyslogSeverity.emergency < SyslogSeverity.error)
        XCTAssertTrue(SyslogSeverity.error < SyslogSeverity.informational)
    }
}
