import Foundation
import Network

public protocol TFTPClientDelegate: AnyObject {
    func tftpClientDidLog(_ message: String, isError: Bool)
    func tftpClientProgressUpdated(bytesTransferred: Int64, totalBytes: Int64?, speedBytesPerSec: Double, progress: Double)
    func tftpClientDidComplete(success: Bool, message: String)
}

public final class TFTPClientService {
    public weak var delegate: TFTPClientDelegate?
    
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.systftp.client.tftp", qos: .userInitiated)
    private var isCancelled = false
    
    private var startTime: Date = Date()
    private var bytesTransferred: Int64 = 0
    private var totalBytes: Int64?
    private var blksize: Int = 512
    private var currentBlock: UInt16 = 0
    private var fileData = Data()
    private var localFileURL: URL?
    
    public init() {}
    
    public func startTransfer(config: TFTPClientConfig) {
        cancel()
        isCancelled = false
        startTime = Date()
        bytesTransferred = 0
        currentBlock = 0
        fileData = Data()
        blksize = config.enableBlockSizeNegotiation ? config.blockSize : 512
        
        let host = NWEndpoint.Host(config.serverHost)
        guard let port = NWEndpoint.Port(rawValue: UInt16(config.serverPort)) else {
            delegate?.tftpClientDidComplete(success: false, message: "无效的服务器端口：\(config.serverPort)")
            return
        }
        
        let parameters = NWParameters.udp
        let newConnection = NWConnection(host: host, port: port, using: parameters)
        self.connection = newConnection
        
        newConnection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.delegate?.tftpClientDidLog("已连接到 TFTP 服务器 \(config.serverHost):\(config.serverPort)", isError: false)
                if config.isUpload {
                    self.performUpload(config: config)
                } else {
                    self.performDownload(config: config)
                }
            case .failed(let error):
                self.delegate?.tftpClientDidComplete(success: false, message: "连接错误：\(error.localizedDescription)")
            default:
                break
            }
        }
        
        newConnection.start(queue: queue)
    }
    
    public func cancel() {
        isCancelled = true
        connection?.cancel()
        connection = nil
    }
    
    private func performDownload(config: TFTPClientConfig) {
        localFileURL = URL(fileURLWithPath: config.localFilePath)
        var packet = Data([0x00, 0x01]) // RRQ
        
        // Remote filename
        if let fnData = config.remoteFilePath.data(using: .utf8) {
            packet.append(fnData)
        }
        packet.append(0x00)
        
        // Mode
        if let modeData = config.mode.data(using: .utf8) {
            packet.append(modeData)
        }
        packet.append(0x00)
        
        // Options
        if config.enableBlockSizeNegotiation {
            appendOption(to: &packet, name: "blksize", value: "\(config.blockSize)")
        }
        if config.enableTimeoutNegotiation {
            appendOption(to: &packet, name: "timeout", value: "\(config.timeoutSeconds)")
        }
        if config.enableTransferSizeNegotiation {
            appendOption(to: &packet, name: "tsize", value: "0")
        }
        
        delegate?.tftpClientDidLog("正在请求下载 '\(config.remoteFilePath)'（RRQ）…", isError: false)
        
        connection?.send(content: packet, completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.delegate?.tftpClientDidComplete(success: false, message: "发送下载请求（RRQ）失败：\(error.localizedDescription)")
                return
            }
            self?.receiveNextPacket(isUpload: false)
        })
    }
    
    private func performUpload(config: TFTPClientConfig) {
        let fileURL = URL(fileURLWithPath: config.localFilePath)
        guard let data = try? Data(contentsOf: fileURL) else {
            delegate?.tftpClientDidComplete(success: false, message: "无法读取本地文件：\(config.localFilePath)")
            return
        }
        self.fileData = data
        self.totalBytes = Int64(data.count)
        
        var packet = Data([0x00, 0x02]) // WRQ
        if let fnData = config.remoteFilePath.data(using: .utf8) {
            packet.append(fnData)
        }
        packet.append(0x00)
        
        if let modeData = config.mode.data(using: .utf8) {
            packet.append(modeData)
        }
        packet.append(0x00)
        
        if config.enableBlockSizeNegotiation {
            appendOption(to: &packet, name: "blksize", value: "\(config.blockSize)")
        }
        if config.enableTimeoutNegotiation {
            appendOption(to: &packet, name: "timeout", value: "\(config.timeoutSeconds)")
        }
        if config.enableTransferSizeNegotiation {
            appendOption(to: &packet, name: "tsize", value: "\(data.count)")
        }
        
        delegate?.tftpClientDidLog("正在请求上传 '\(config.remoteFilePath)'（WRQ，共 \(data.count) 字节）…", isError: false)
        
        connection?.send(content: packet, completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.delegate?.tftpClientDidComplete(success: false, message: "发送上传请求（WRQ）失败：\(error.localizedDescription)")
                return
            }
            self?.receiveNextPacket(isUpload: true)
        })
    }
    
    private func appendOption(to data: inout Data, name: String, value: String) {
        if let n = name.data(using: .utf8), let v = value.data(using: .utf8) {
            data.append(n)
            data.append(0x00)
            data.append(v)
            data.append(0x00)
        }
    }
    
    private func receiveNextPacket(isUpload: Bool) {
        guard !isCancelled, let conn = connection else { return }
        
        conn.receiveMessage { [weak self] content, context, isComplete, error in
            guard let self = self, !self.isCancelled else { return }
            
            if let error = error {
                self.delegate?.tftpClientDidComplete(success: false, message: "接收错误：\(error.localizedDescription)")
                return
            }
            
            guard let data = content, data.count >= 2 else {
                self.receiveNextPacket(isUpload: isUpload)
                return
            }
            
            let opcode = UInt16(data[0]) << 8 | UInt16(data[1])
            
            switch opcode {
            case 3: // DATA (Download)
                self.handleIncomingData(data: data)
            case 4: // ACK (Upload)
                self.handleIncomingAck(data: data)
            case 5: // ERROR
                let msg = self.parseErrorMessage(data: data)
                self.delegate?.tftpClientDidComplete(success: false, message: "服务器错误：\(msg)")
                self.cancel()
            case 6: // OACK (Option Acknowledgement)
                self.handleOack(data: data, isUpload: isUpload)
            default:
                self.delegate?.tftpClientDidComplete(success: false, message: "意外的操作码：\(opcode)")
            }
        }
    }
    
    private func handleOack(data: Data, isUpload: Bool) {
        let options = parseOptions(data: data.subdata(in: 2..<data.count))
        if let blk = options["blksize"], let b = Int(blk) {
            self.blksize = b
        }
        if let tsz = options["tsize"], let t = Int64(tsz) {
            self.totalBytes = t
        }
        delegate?.tftpClientDidLog("服务器已接受协商选项：\(options)", isError: false)
        
        if isUpload {
            currentBlock = 1
            sendNextUploadBlock()
        } else {
            // Send ACK 0
            sendAck(blockNum: 0)
            receiveNextPacket(isUpload: false)
        }
    }
    
    private func handleIncomingData(data: Data) {
        guard data.count >= 4 else { return }
        let blockNum = UInt16(data[2]) << 8 | UInt16(data[3])
        let payload = data.subdata(in: 4..<data.count)
        
        let expectedBlock = (currentBlock == 65535) ? 0 : (currentBlock + 1)
        if blockNum == expectedBlock {
            currentBlock = blockNum
            fileData.append(payload)
            bytesTransferred += Int64(payload.count)
            notifyProgress()
            
            sendAck(blockNum: currentBlock)
            
            if payload.count < blksize {
                // Finished download!
                if let url = localFileURL {
                    do {
                        try fileData.write(to: url)
                        delegate?.tftpClientDidComplete(success: true, message: "下载完成：已将 \(bytesTransferred) 字节保存至 \(url.lastPathComponent)")
                    } catch {
                        delegate?.tftpClientDidComplete(success: false, message: "文件保存到磁盘失败：\(error.localizedDescription)")
                    }
                } else {
                    delegate?.tftpClientDidComplete(success: true, message: "下载完成（\(bytesTransferred) 字节）")
                }
                cancel()
                return
            }
        } else if blockNum == currentBlock {
            sendAck(blockNum: currentBlock)
        }
        
        receiveNextPacket(isUpload: false)
    }
    
    private func handleIncomingAck(data: Data) {
        guard data.count >= 4 else { return }
        let ackBlock = UInt16(data[2]) << 8 | UInt16(data[3])
        
        if ackBlock == 0 && currentBlock == 0 {
            currentBlock = 1
            sendNextUploadBlock()
            return
        }
        
        if ackBlock == currentBlock {
            bytesTransferred = min(Int64(fileData.count), Int64(currentBlock) * Int64(blksize))
            notifyProgress()
            
            let offset = Int(currentBlock - 1) * blksize
            if offset + blksize >= fileData.count {
                delegate?.tftpClientDidComplete(success: true, message: "上传完成（已发送 \(bytesTransferred) 字节）")
                cancel()
                return
            }
            
            currentBlock = (currentBlock == 65535) ? 0 : (currentBlock + 1)
            sendNextUploadBlock()
        }
    }
    
    private func sendNextUploadBlock() {
        guard !isCancelled, let conn = connection else { return }
        let offset = Int(currentBlock - 1) * blksize
        guard offset < fileData.count else { return }
        let end = min(offset + blksize, fileData.count)
        let chunk = fileData.subdata(in: offset..<end)
        
        var packet = Data([0x00, 0x03, UInt8(currentBlock >> 8), UInt8(currentBlock & 0xFF)])
        packet.append(chunk)
        
        conn.send(content: packet, completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.delegate?.tftpClientDidComplete(success: false, message: "发送 DATA 失败：\(error.localizedDescription)")
                return
            }
            self?.receiveNextPacket(isUpload: true)
        })
    }
    
    private func sendAck(blockNum: UInt16) {
        let ack = Data([0x00, 0x04, UInt8(blockNum >> 8), UInt8(blockNum & 0xFF)])
        connection?.send(content: ack, completion: .contentProcessed({ _ in }))
    }
    
    private func notifyProgress() {
        let elapsed = max(0.001, Date().timeIntervalSince(startTime))
        let speed = Double(bytesTransferred) / elapsed
        let prog = (totalBytes != nil && totalBytes! > 0) ? min(1.0, Double(bytesTransferred) / Double(totalBytes!)) : 0.0
        delegate?.tftpClientProgressUpdated(
            bytesTransferred: bytesTransferred,
            totalBytes: totalBytes,
            speedBytesPerSec: speed,
            progress: prog
        )
    }
    
    private func parseOptions(data: Data) -> [String: String] {
        var strings: [String] = []
        var cur = Data()
        for b in data {
            if b == 0 {
                if let str = String(data: cur, encoding: .utf8) {
                    strings.append(str)
                }
                cur.removeAll()
            } else {
                cur.append(b)
            }
        }
        var opts: [String: String] = [:]
        var i = 0
        while i + 1 < strings.count {
            opts[strings[i].lowercased()] = strings[i+1]
            i += 2
        }
        return opts
    }
    
    private func parseErrorMessage(data: Data) -> String {
        guard data.count > 4 else { return "未知错误" }
        return String(data: data.subdata(in: 4..<data.count), encoding: .utf8) ?? "TFTP 错误 \(data[2])\(data[3])"
    }
}
