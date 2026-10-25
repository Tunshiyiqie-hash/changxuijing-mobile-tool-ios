//
//  LanLink.swift
//  长须鲸手机工具 - 局域网 TCP 链路（NWConnection 封装）
//  承载：握手 JSON 行 + 控制 JSON 行（\n 结尾）+ 二进制帧 [4BE 头长][JSON 头][负载]
//  与远程 WSGateway 上的消息格式保持一致（协议 §3）。
//

import Foundation
import Network

protocol LanLinkDelegate: AnyObject {
    func linkDidOpen(_ link: LanLink)
    func link(_ link: LanLink, didControl msg: [String: Any])
    func link(_ link: LanLink, didBinary header: [String: Any], payload: Data)
    func linkDidClose(_ link: LanLink)
}

final class LanLink: NSObject {
    weak var delegate: LanLinkDelegate?
    let connection: NWConnection

    /// 本端角色：initiator / responder
    var role: String = "initiator"
    var peerName = ""
    var peerFp = ""
    var peerPlatform = ""
    var peerAccount = ""
    var isConnected = false

    // MARK: 流重组状态机
    private enum Phase {
        case text          // 等待一条 \n 结尾的 JSON 控制行
        case binHeaderLen  // 等待 4 字节大端头长
        case binHeaderBody// 等待头 JSON 体
        case binPayload    // 等待负载
    }
    private var phase: Phase = .text
    private var buffer = Data()
    private var binHeaderLen: Int?
    private var binHeader: [String: Any]?
    private var binPayloadLen: Int = 0
    private var binPayload = Data()

    // MARK: 初始化
    init(to endpoint: NWEndpoint) {
        connection = NWConnection(to: endpoint, using: .tcp)
        super.init()
    }

    init(accepted connection: NWConnection) {
        self.connection = connection
        super.init()
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.isConnected = true
                self.delegate?.linkDidOpen(self)
                self.receiveLoop()
            case .failed, .cancelled:
                self.isConnected = false
                self.delegate?.linkDidClose(self)
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    func close() {
        isConnected = false
        connection.cancel()
    }

    // MARK: 发送
    func sendControl(_ msg: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: msg, options: []) else { return }
        var out = d
        out.append(0x0A)
        connection.send(content: out, completion: .contentProcessed { _ in })
    }

    func sendHandshake(role: String, name: String, pf: String, fp: String) {
        sendControl(["proto": "cxj-link", "v": 1, "role": role,
                     "name": name, "pf": pf, "fp": fp])
    }

    func sendBinary(header: [String: Any], payload: Data) {
        var h = header
        h["len"] = payload.count
        connection.send(content: FrameCoder.encode(header: h, payload: payload),
                        completion: .contentProcessed { _ in })
    }

    // MARK: 接收
    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data { self.buffer.append(data) }
            self.processBuffer()
            if isComplete || error != nil {
                self.delegate?.linkDidClose(self)
                return
            }
            self.receiveLoop()
        }
    }

    private func processBuffer() {
        while true {
            switch phase {
            case .text:
                guard let first = buffer.first else { return }
                // 控制行以 '{' 开头；二进制帧头长首字节通常为 0，进入二进制阶段
                if first != 0x7B {
                    phase = .binHeaderLen
                    continue
                }
                guard let nl = buffer.firstIndex(of: 0x0A) else { return }
                let line = buffer.prefix(upTo: nl)
                buffer.removeSubrange(0...nl)
                if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                    delegate?.link(self, didControl: obj)
                }

            case .binHeaderLen:
                guard buffer.count >= 4 else { return }
                let n = Int(UInt32(buffer[0]) << 24 | UInt32(buffer[1]) << 16 |
                            UInt32(buffer[2]) << 8 | UInt32(buffer[3]))
                buffer.removeSubrange(0..<4)
                binHeaderLen = n
                phase = .binHeaderBody

            case .binHeaderBody:
                guard let n = binHeaderLen else { phase = .text; binHeaderLen = nil; continue }
                guard buffer.count >= n else { return }
                let headerData = buffer.prefix(n)
                buffer.removeSubrange(0..<n)
                if let h = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any] {
                    binHeader = h
                    binPayloadLen = (h["len"] as? Int) ?? 0
                    binPayload = Data()
                    phase = .binPayload
                } else {
                    phase = .text
                    binHeaderLen = nil
                }

            case .binPayload:
                let need = binPayloadLen - binPayload.count
                guard need > 0 else {
                    phase = .text
                    if let h = binHeader { delegate?.link(self, didBinary: h, payload: binPayload) }
                    binHeader = nil
                    continue
                }
                guard buffer.count > 0 else { return }
                let take = min(need, buffer.count)
                binPayload.append(buffer.prefix(take))
                buffer.removeSubrange(0..<take)
                if binPayload.count == binPayloadLen {
                    let h = binHeader ?? [:]
                    binHeader = nil
                    phase = .text
                    delegate?.link(self, didBinary: h, payload: binPayload)
                }
            }
        }
    }
}
