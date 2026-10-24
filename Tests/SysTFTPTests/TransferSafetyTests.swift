import XCTest
@testable import SysTFTP

final class TransferSafetyTests: XCTestCase {
    func testBlockNumbersWrapAndExactSizeSendsAnEmptyBlock() {
        XCTAssertEqual(TFTPBlocks.number(forIndex: 0), 1)
        XCTAssertEqual(TFTPBlocks.number(forIndex: 65534), 65535)
        XCTAssertEqual(TFTPBlocks.number(forIndex: 65535), 0)
        XCTAssertEqual(TFTPBlocks.number(forIndex: 65536), 1)
        XCTAssertEqual(TFTPBlocks.length(fileSize: 512, index: 0, blksize: 512), 512 as Int?)
        XCTAssertEqual(TFTPBlocks.length(fileSize: 512, index: 1, blksize: 512), 0 as Int?)
        XCTAssertNil(TFTPBlocks.length(fileSize: 100, index: 1, blksize: 512))
        XCTAssertEqual(TFTPBlocks.length(fileSize: 0, index: 0, blksize: 512), 0 as Int?)
        let wrappedOffset = Int64(65536) * 512
        XCTAssertEqual(TFTPBlocks.length(fileSize: wrappedOffset, index: 65535, blksize: 512), 512 as Int?)
        XCTAssertEqual(TFTPBlocks.length(fileSize: wrappedOffset, index: 65536, blksize: 512), 0 as Int?)
    }

    func testFileReadKeepsGoingUntilTheRequestedBlockIsFull() throws {
        let url = temporaryDirectory().appendingPathComponent("block.bin")
        let payload = Data(repeating: 7, count: 600)
        try payload.write(to: url)
        let handle = try FileHandle(forReadingFrom: url)
        let data = try TFTPFiles.read(handle, count: 512)
        try handle.close()
        XCTAssertEqual(data, payload.prefix(512))
        XCTAssertEqual(try TFTPFiles.read(nil, count: 0), Data())
    }

    func testParentPathAndSymlinkCannotEscape() throws {
        let root = temporaryDirectory()
        let outside = root.deletingLastPathComponent().appendingPathComponent("secret-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: outside.appendingPathComponent("note"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: outside)
        XCTAssertNil(FTPPaths.resolve(root: root.path, currentVirtual: "/", requested: "/.."))
        XCTAssertNil(FTPPaths.resolve(root: root.path, currentVirtual: "/", requested: "../../etc/passwd"))
        XCTAssertNil(PathJail.resolve(root: root.path, relative: "link/note"))
        XCTAssertEqual(
            PathJail.resolve(root: root.path, relative: "./a.txt").map { URL(fileURLWithPath: $0).lastPathComponent },
            "a.txt"
        )
        let kept = FTPPaths.resolve(root: root.path, currentVirtual: "/", requested: "a.txt")
        XCTAssertEqual(
            URL(fileURLWithPath: kept?.actual ?? "").resolvingSymlinksInPath().path,
            root.appendingPathComponent("a.txt").resolvingSymlinksInPath().path
        )
        try? FileManager.default.removeItem(at: outside)
        XCTAssertEqual(FTPPaths.resolve(root: root.path, currentVirtual: "/docs", requested: "..")?.virtual, "/")
    }

    func testPortToAnotherHostIsRejected() {
        XCTAssertNil(FTPPorts.parse("1,2,3"))
        XCTAssertEqual(FTPPorts.parse("10,0,0,5,19,136")?.port, 5000 as UInt16)
        XCTAssertFalse(FTPPorts.allows(clientIP: "10.0.0.5", host: "10.0.0.9"))
        XCTAssertTrue(FTPPorts.allows(clientIP: "::ffff:10.0.0.5", host: "10.0.0.5"))
    }

    func testStoredHashIsNotAcceptedAsThePassword() {
        let user = FTPUser(username: "admin", password: "secretpassword", userDirectory: "/tmp")
        XCTAssertTrue(user.verifyPassword("secretpassword"))
        XCTAssertFalse(user.verifyPassword(user.passwordHash))
        XCTAssertFalse(FTPUser(username: "new", password: "", userDirectory: "/tmp").verifyPassword(""))
        XCTAssertFalse(FTPUser(username: "new", password: "", userDirectory: "/tmp").verifyPassword("password123"))
        XCTAssertTrue(FTPServerConfig().blocksStartup == false)
        var config = FTPServerConfig()
        config.users.append(FTPUser(username: "open", password: "", userDirectory: "/tmp", canLogin: true))
        XCTAssertTrue(config.blocksStartup)
    }

    func testExactAndShortTransfersRoundTripOnLocalhost() throws {
        let root = temporaryDirectory()
        let exact = Data(repeating: 0xAB, count: 512)
        let short = Data(repeating: 0xCD, count: 513)
        try exact.write(to: root.appendingPathComponent("exact.bin"))
        var config = TFTPServerConfig()
        config.port = 0
        config.rootDirectory = root.path
        config.timeoutSeconds = 1
        config.maxRetries = 2
        let server = TFTPServerService(config: config)
        let serverDelegate = ServerBox()
        server.delegate = serverDelegate
        try server.start()
        defer { server.stop() }
        XCTAssertGreaterThan(server.listeningPort, 0)

        let exactFile = try transfer(upload: false, port: server.listeningPort, remote: "exact.bin", local: root.appendingPathComponent("down-exact.bin"), payload: nil)
        XCTAssertEqual(exactFile, exact)
        let uploaded = root.appendingPathComponent("source.bin")
        _ = try transfer(upload: true, port: server.listeningPort, remote: "up.bin", local: uploaded, payload: short)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("up.bin")), short)
        server.stop()
    }

    func testClientGivesUpWhenNobodyAnswers() {
        let client = TFTPClientService()
        let box = ClientBox()
        client.delegate = box
        var config = TFTPClientConfig()
        config.serverHost = "127.0.0.1"
        config.serverPort = Int(freeUDPPort())
        config.timeoutSeconds = 1
        config.enableBlockSizeNegotiation = false
        config.enableTimeoutNegotiation = false
        config.enableTransferSizeNegotiation = false
        config.remoteFilePath = "missing.bin"
        config.localFilePath = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).bin").path
        config.isUpload = false
        client.startTransfer(config: config)
        wait(for: [box.done], timeout: 12)
        XCTAssertEqual(box.success, false)
    }

    func testSameSourcePortDeliversEverySyslogDatagram() throws {
        let port = freeUDPPort()
        var config = SyslogConfig()
        config.port = Int(port)
        config.saveToFile = false
        let server = SyslogServerService(config: config)
        let box = SyslogBox()
        server.delegate = box
        try server.start()
        defer { server.stop() }
        wait(for: [box.ready], timeout: 2)
        let socket = try UDPSocket(port: 0)
        let peer = IPv4Peer.resolve(host: "127.0.0.1", port: port)!
        try socket.send(Data("<13>one".utf8), to: peer)
        try socket.send(Data("<13>two".utf8), to: peer)
        socket.close()
        wait(for: [box.gotTwo], timeout: 2)
        XCTAssertEqual(box.messages.map(\.message), ["one", "two"])
    }

    private func transfer(upload: Bool, port: Int, remote: String, local: URL, payload: Data?) throws -> Data? {
        if let payload { try payload.write(to: local) }
        let client = TFTPClientService()
        let box = ClientBox()
        client.delegate = box
        var config = TFTPClientConfig()
        config.serverHost = "127.0.0.1"
        config.serverPort = port
        config.isUpload = upload
        config.remoteFilePath = remote
        config.localFilePath = local.path
        config.timeoutSeconds = 1
        config.enableBlockSizeNegotiation = false
        config.enableTimeoutNegotiation = false
        config.enableTransferSizeNegotiation = false
        client.startTransfer(config: config)
        wait(for: [box.done], timeout: 8)
        XCTAssertEqual(box.success, true, box.message)
        return upload ? nil : try Data(contentsOf: local)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("systftp-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func freeUDPPort() -> UInt16 {
        let socket = try! UDPSocket(port: 0)
        let port = socket.localPort()
        socket.close()
        return port
    }
}

private final class ServerBox: TFTPServerDelegate {
    func tftpServerDidLog(_ message: String, isError: Bool) {}
    func tftpServerTransferUpdated(_ item: TFTPTransferItem) {}
    func tftpServerStatusChanged(isRunning: Bool, port: Int) {}
}

private final class ClientBox: TFTPClientDelegate {
    let done = XCTestExpectation(description: "transfer finished")
    var success: Bool?
    var message = ""
    func tftpClientDidLog(_ message: String, isError: Bool) {}
    func tftpClientProgressUpdated(bytesTransferred: Int64, totalBytes: Int64?, speedBytesPerSec: Double, progress: Double) {}
    func tftpClientDidComplete(success: Bool, message: String) {
        self.success = success
        self.message = message
        done.fulfill()
    }
}

private final class SyslogBox: SyslogServerDelegate, @unchecked Sendable {
    let gotTwo = XCTestExpectation(description: "two syslog messages")
    let ready = XCTestExpectation(description: "syslog ready")
    var messages: [SyslogMessage] = []
    private let lock = NSLock()
    func syslogServerDidReceive(messages: [SyslogMessage]) {
        lock.lock()
        self.messages.append(contentsOf: messages)
        let count = self.messages.count
        lock.unlock()
        if count >= 2 { gotTwo.fulfill() }
    }
    func syslogServerDidLog(_ text: String, isError: Bool) {}
    func syslogServerStatusChanged(isRunning: Bool, port: Int) {
        if isRunning { ready.fulfill() }
    }
}
