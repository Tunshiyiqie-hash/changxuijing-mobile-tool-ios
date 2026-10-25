//
//  AppState.swift
//  长须鲸手机工具 - 全局状态（登录/离线/越狱分叉/网关/局域网配对/屏幕查看/文件会话）
//

import SwiftUI
import UIKit
import Network

// MARK: - 待确认配对（被连方弹窗）

struct PendingPair: Identifiable {
    let id: String
    let peerName: String
    let platform: String
    let account: String
    let peerFp: String
    let link: LanLink
}

// MARK: - 待确认动作（屏幕/文件/紧急申请，目标端弹窗）

struct PendingAsk: Identifiable {
    let id: String            // sid
    let kind: String          // screen_ask / file_ask / pull_ask / screen_offer
    let fromName: String
    let platform: String
    let fileName: String
    let size: Int64
    let sha256: String
    let pullKind: String      // screen / file（pull_ask 用）
    let link: LanLink?        // 局域网链路；nil 表示远程网关
    let onAccept: () -> Void
    let onDeny: () -> Void
}

final class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: 门禁
    @Published var loggedIn: Bool
    @Published var needsSetCode: Bool
    @Published var offlineMode: Bool {
        didSet {
            UserDefaults.standard.set(offlineMode, forKey: "offline_mode")
            if offlineMode { stopDiscovery() } else if loggedIn { startDiscovery() }
        }
    }
    @Published var jailbroken: Bool

    // MARK: 账号/设备
    @Published var loginName: String = ""
    @Published var remoteDevices: [RemoteDevice] = []
    @Published var toast: String = ""

    // MARK: 屏幕查看（看对端屏幕）
    @Published var viewingImage: UIImage?
    @Published var viewingActive: Bool = false
    @Published var currentViewSid: String = ""

    // MARK: 配对 / 询问弹窗
    @Published var pendingPair: PendingPair?
    @Published var pendingAsk: PendingAsk?
    @Published var pairBanner: String = ""

    // MARK: 网关
    private var ws: WSGateway?

    // MARK: 局域网
    private var activeLink: LanLink?
    private var pendingOutgoingLink: LanLink?
    private var pendingIncomingLink: LanLink?
    private var pendingOutgoingPeer: Peer?

    // MARK: 文件会话
    private var outgoingFile: (sid: String, data: Data, name: String, sha256: String, link: LanLink?)?
    private var incomingRemoteFile: (sid: String, name: String, size: Int64, sha256: String)?

    // MARK: 本地指纹
    let fp: String

    private init() {
        loggedIn = APIClient.shared.userToken != nil
        needsSetCode = APIClient.shared.userToken != nil && !(APIClient.shared.codeSet)
        offlineMode = UserDefaults.standard.bool(forKey: "offline_mode")
        jailbroken = Jailbreak.shared.isJailbroken
        fp = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        loginName = APIClient.shared.loginName ?? ""
        Discovery.shared.app = self
    }

    // MARK: - 登录后调用
    func onLoggedIn(token: String, login: String, codeSet: Bool) {
        APIClient.shared.setUserToken(token)
        APIClient.shared.setLoginName(login)
        APIClient.shared.setCodeSet(codeSet)
        loginName = login
        loggedIn = true
        needsSetCode = !codeSet
        registerDeviceIfNeeded()
    }

    func logout() {
        ws?.disconnect()
        activeLink?.close()
        activeLink = nil
        stopDiscovery()
        APIClient.shared.setUserToken(nil)
        APIClient.shared.setLoginName(nil)
        APIClient.shared.setDeviceToken(nil)
        APIClient.shared.setDeviceId(nil)
        APIClient.shared.setCodeSet(false)
        loggedIn = false
        needsSetCode = false
        remoteDevices = []
        viewingActive = false
        viewingImage = nil
        pendingPair = nil
        pendingAsk = nil
    }

    func registerDeviceIfNeeded() {
        let name = UIDevice.current.name
        APIClient.shared.registerDevice(name: name, fp: fp) { [weak self] r in
            guard let self = self else { return }
            switch r {
            case .success(let d):
                APIClient.shared.setDeviceId(d.deviceId)
                APIClient.shared.setDeviceToken(d.deviceToken)
                GroupDefaults.set("device_token", d.deviceToken)
                self.connectGateway()
                self.refreshDevices()
                self.startDiscovery()
            case .failure(let e):
                self.toast = "设备注册失败：\(e)"
            }
        }
    }

    func refreshDevices() {
        APIClient.shared.me { [weak self] r in
            guard let self = self else { return }
            if case .success(let ds) = r { self.remoteDevices = ds }
        }
    }

    // MARK: - 发现开关
    func startDiscovery() {
        guard loggedIn, !offlineMode else { return }
        Discovery.shared.start()
    }

    func stopDiscovery() {
        Discovery.shared.stop()
    }

    // MARK: - 网关
    func connectGateway() {
        guard let dt = APIClient.shared.deviceToken, !dt.isEmpty else { return }
        ws?.disconnect()
        let w = WSGateway(deviceToken: dt)
        w.delegate = self
        ws = w
        w.connect()
    }

    // MARK: - 统一发送（优先局域网已配对链路，否则远程网关）
    func sendControl(_ msg: [String: Any]) {
        if let link = activeLink, link.isConnected {
            link.sendControl(msg)
        } else {
            ws?.send(json: msg)
        }
    }

    func sendBinary(header: [String: Any], payload: Data) {
        if let link = activeLink, link.isConnected {
            link.sendBinary(header: header, payload: payload)
        } else {
            ws?.send(data: FrameCoder.encode(header: header, payload: payload))
        }
    }

    // MARK: - 远程：拉屏幕 / 拉文件 / 发文件
    func pullScreen(to device: RemoteDevice) {
        guard device.online else { toast = "设备离线"; return }
        let sid = Config.makeSid()
        startViewing(sid: sid)
        var msg: [String: Any] = ["t": "pull", "kind": "screen", "sid": sid]
        msg["to"] = ["device_id": device.deviceId]
        sendControl(msg)
    }

    func pullFile(to device: RemoteDevice) {
        guard device.online else { toast = "设备离线"; return }
        let sid = Config.makeSid()
        var msg: [String: Any] = ["t": "pull", "kind": "file", "sid": sid]
        msg["to"] = ["device_id": device.deviceId]
        sendControl(msg)
        toast = "已申请对方发送文件，等待对方确认"
    }

    /// 向当前已配对的局域网设备发送文件
    func offerLanFile(url: URL) {
        guard let link = activeLink, link.isConnected else {
            toast = "尚无已配对的局域网设备"
            return
        }
        guard let data = try? Data(contentsOf: url) else { toast = "无法读取文件"; return }
        let sid = Config.makeSid()
        let sha = FileHash.sha256Hex(data)
        let name = url.lastPathComponent
        outgoingFile = (sid, data, name, sha, link)
        link.sendControl(["t": "file_offer", "sid": sid, "name": name,
                          "size": data.count, "sha256": sha])
        toast = "已向局域网设备发送文件请求"
    }

    func offerRemoteFile(url: URL, to device: RemoteDevice) {
        guard let data = try? Data(contentsOf: url) else { toast = "无法读取文件"; return }
        let sid = Config.makeSid()
        let sha = FileHash.sha256Hex(data)
        let name = url.lastPathComponent
        outgoingFile = (sid, data, name, sha, nil)
        var msg: [String: Any] = ["t": "file_offer", "sid": sid, "name": name,
                                  "size": data.count, "sha256": sha]
        msg["to"] = ["device_id": device.deviceId]
        sendControl(msg)
        toast = "已向 \(device.name) 发送文件请求"
    }

    // MARK: - 会话状态
    func startViewing(sid: String) {
        currentViewSid = sid
        viewingActive = true
        viewingImage = nil
    }

    func stopViewing() {
        viewingActive = false
        viewingImage = nil
        if !currentViewSid.isEmpty {
            sendControl(["t": "screen_stop", "sid": currentViewSid])
        }
        currentViewSid = ""
    }

    // MARK: - 配对：主动发起（手机点电脑/其他设备）
    func beginOutgoingPair(_ link: LanLink, peer: Peer) {
        pendingOutgoingLink = link
        pendingOutgoingPeer = peer
        link.delegate = self
        link.start()
    }

    // MARK: - 配对：被动接受（被电脑/其他手机连接）
    func handleIncomingLink(_ link: LanLink) {
        pendingIncomingLink = link
        link.delegate = self
        link.start()
    }

    func acceptPair(_ accept: Bool) {
        guard let p = pendingPair else { return }
        if accept {
            Discovery.shared.trust(p.peerFp)
            activeLink = p.link
            p.link.sendControl(["t": "pair_result", "accept": true,
                                "name": UIDevice.current.name, "pf": "ios",
                                "fp": fp, "trust": true])
            pairBanner = "已连接：\(p.peerName)"
            toast = "已连接：\(p.peerName)"
            Discovery.shared.pairStatus[p.peerFp] = "connected"
        } else {
            p.link.sendControl(["t": "pair_result", "accept": false,
                                 "name": UIDevice.current.name, "pf": "ios", "fp": fp])
            p.link.close()
            Discovery.shared.pairStatus[p.peerFp] = "rejected"
            toast = "已拒绝 \(p.peerName) 的配对"
        }
        pendingPair = nil
    }

    // MARK: - 询问弹窗应答
    func acceptAsk() {
        guard let ask = pendingAsk else { return }
        ask.onAccept()
        pendingAsk = nil
    }

    func denyAsk() {
        guard let ask = pendingAsk else { return }
        ask.onDeny()
        pendingAsk = nil
    }

    // MARK: - 统一控制消息分发（网关 / 局域网共用）
    private func handleControl(_ msg: [String: Any], link: LanLink?) {
        let t = msg["t"] as? String ?? ""
        switch t {
        case "hello_ack":
            break
        case "pong":
            break
        case "ping":
            sendControl(["t": "pong"])
        case "presence":
            if let arr = msg["devices"] as? [[String: Any]] {
                remoteDevices = arr.map { d in
                    RemoteDevice(deviceId: (d["device_id"] as? String) ?? "",
                                 name: (d["name"] as? String) ?? "未知",
                                 platform: (d["platform"] as? String) ?? "",
                                 online: (d["online"] as? Bool) ?? false,
                                 lastSeen: nil)
                }
            }

        // MARK: 配对握手
        case "pair_request":
            handlePairRequest(msg, link: link)
        case "pair_result":
            handlePairResult(msg, link: link)

        // MARK: 屏幕 / 文件询问
        case "screen_offer", "screen_ask", "pull_ask", "file_ask":
            queueAsk(msg, link: link)
        case "answer":
            handleAnswer(msg)
        case "go":
            handleGo(msg)
        case "deny":
            toast = "对方拒绝了请求：\(msg["reason"] as? String ?? "")"
            viewingActive = false
            viewingImage = nil
        case "end", "screen_stop":
            viewingActive = false
            viewingImage = nil
        case "file_ready":
            handleFileReady(msg)
        case "file_done":
            toast = "文件已送达对方"
        case "ctrl":
            handleCtrl(msg)
        default:
            break
        }
    }

    private func handlePairRequest(_ msg: [String: Any], link: LanLink?) {
        guard let link = link else { return }
        let name = msg["name"] as? String ?? "未知设备"
        let pf = msg["pf"] as? String ?? "?"
        let peerFp = msg["fp"] as? String ?? ""
        let account = msg["account"] as? String ?? ""
        link.peerName = name
        link.peerPlatform = pf
        link.peerFp = peerFp
        link.peerAccount = account

        if Discovery.shared.isTrusted(peerFp) {
            // 已信任：自动接受
            Discovery.shared.trust(peerFp)
            activeLink = link
            link.sendControl(["t": "pair_result", "accept": true,
                              "name": UIDevice.current.name, "pf": "ios", "fp": fp, "trust": true])
            toast = "已自动接受可信设备：\(name)"
            Discovery.shared.pairStatus[peerFp] = "connected"
        } else {
            pendingPair = PendingPair(id: peerFp, peerName: name, platform: pf,
                                     account: account, peerFp: peerFp, link: link)
        }
    }

    private func handlePairResult(_ msg: [String: Any], link: LanLink?) {
        let accept = msg["accept"] as? Bool ?? false
        let peerName = msg["name"] as? String ?? pendingOutgoingPeer?.name ?? "设备"
        if accept {
            activeLink = link
            if let fp = msg["fp"] as? String { Discovery.shared.trust(fp) }
            if let peer = pendingOutgoingPeer { Discovery.shared.trust(peer.fp) }
            Discovery.shared.pairStatus[pendingOutgoingPeer?.fp ?? ""] = "connected"
            toast = "已连接：\(peerName)"
            pairBanner = "已连接：\(peerName)"
        } else {
            link?.close()
            Discovery.shared.pairStatus[pendingOutgoingPeer?.fp ?? ""] = "rejected"
            toast = "配对被对方拒绝"
        }
        pendingOutgoingLink = nil
        pendingOutgoingPeer = nil
    }

    private func queueAsk(_ msg: [String: Any], link: LanLink?) {
        let sid = msg["sid"] as? String ?? Config.makeSid()
        let from = msg["from"] as? [String: Any]
        let fromName = from?["name"] as? String ?? "未知设备"
        let platform = from?["platform"] as? String ?? "?"
        let kind = msg["kind"] as? String
        let fileName = msg["name"] as? String ?? ""
        let size = (msg["size"] as? Int64) ?? 0
        let sha = msg["sha256"] as? String ?? ""

        let accept: () -> Void = { [weak self] in
            guard let self = self else { return }
            var answer: [String: Any] = ["t": "answer", "sid": sid, "accept": true]
            if let link = link { link.sendControl(answer) } else { self.ws?.send(json: answer) }
            if msg["t"] as? String == "screen_offer" || msg["t"] as? String == "screen_ask" {
                self.startViewing(sid: sid)
            }
        }
        let deny: () -> Void = { [weak self] in
            guard let self = self else { return }
            var answer: [String: Any] = ["t": "answer", "sid": sid, "accept": false]
            if let link = link { link.sendControl(answer) } else { self.ws?.send(json: answer) }
        }

        pendingAsk = PendingAsk(id: sid, kind: msg["t"] as? String ?? "",
                                fromName: fromName, platform: platform,
                                fileName: fileName, size: size, sha256: sha,
                                pullKind: kind ?? "screen", link: link,
                                onAccept: accept, onDeny: deny)

        if msg["t"] as? String == "file_ask" {
            incomingRemoteFile = (sid: sid, name: fileName, size: size, sha256: sha)
        }
    }

    private func handleAnswer(_ msg: [String: Any]) {
        let accept = msg["accept"] as? Bool ?? false
        guard accept, let sid = msg["sid"] as? String else {
            toast = "对方拒绝了文件请求"
            outgoingFile = nil
            return
        }
        if let f = outgoingFile, f.sid == sid {
            // 局域网：直接分块发送；远程：等 go 带 put 路径
            if let link = f.link {
                FileSender.sendChunks(data: f.data, name: f.name, sid: sid,
                                      sha256: f.sha256, over: link) {
                    self.toast = "文件已通过局域网发送"
                }
            }
        }
    }

    private func handleGo(_ msg: [String: Any]) {
        guard let sid = msg["sid"] as? String,
              let f = outgoingFile, f.sid == sid else { return }
        // 远程：PUT 到 relay
        APIClient.shared.relayPut(sid: sid, data: f.data) { r in
            switch r {
            case .success:
                self.sendControl(["t": "file_ready", "sid": sid])
                self.toast = "文件已上传到中继，等待对方接收"
            case .failure(let e):
                self.toast = "文件上传失败：\(e)"
            }
        }
    }

    private func handleFileReady(_ msg: [String: Any]) {
        guard let sid = msg["sid"] as? String else { return }
        APIClient.shared.relayGet(sid: sid) { r in
            switch r {
            case .success(let data):
                if let info = self.incomingRemoteFile, info.sid == sid,
                   !info.sha256.isEmpty, FileHash.sha256Hex(data) != info.sha256 {
                    self.toast = "文件校验失败，已丢弃"
                    return
                }
                // 落盘到临时目录，再弹分享面板
                let dir = NSTemporaryDirectory()
                let name = self.incomingRemoteFile?.name ?? "接收文件"
                let url = URL(fileURLWithPath: dir).appendingPathComponent("cxj_recv_\(sid)_\(name)")
                try? data.write(to: url, options: .atomic)
                APIClient.shared.relayAck(sid: sid) {}
                self.sendControl(["t": "file_done", "sid": sid])
                self.incomingRemoteFile = nil
                self.showReceivedFile(url: url, name: name)
            case .failure(let e):
                self.toast = "文件下载失败：\(e)"
            }
        }
    }

    /// 接收文件后弹出系统分享面板落盘（由 DevicesView/主界面监听 pendingShareURL）
    @Published var pendingShareURL: URL?

    func showReceivedFile(url: URL, name: String) {
        pendingShareURL = url
        toast = "已接收文件：\(name)，请选择保存位置"
    }

    private func handleCtrl(_ msg: [String: Any]) {
        // 未越狱：仅可看，不接收/执行任何控制注入（协议 §3.4 / §5）
        guard jailbroken else { return }
        let action = msg["action"] as? String ?? ""
        switch action {
        case "pointer":
            let ev = msg["ev"] as? String ?? "down"
            let x = msg["x"] as? Double ?? 0
            let y = msg["y"] as? Double ?? 0
            ControlInjector.shared.tap(nx: x, ny: y, phase: ev)
        case "key":
            ControlInjector.shared.press(msg["code"] as? String ?? "")
        case "text":
            ControlInjector.shared.typeText(msg["text"] as? String ?? "")
        case "flash":
            JBManager.shared.flash(mode: msg["mode"] as? String ?? "restart")
        case "install_ipa":
            toast = "收到远程安装 IPA 指令，等待文件传输"
        default:
            break
        }
    }

    // MARK: - 局域网二进制帧分发
    private func handleBinary(header: [String: Any], payload: Data) {
        if header["t"] as? String == "file" {
            if let url = LanFileReceiver.shared.addChunk(header: header, payload: payload) {
                let name = header["name"] as? String ?? "接收文件"
                showReceivedFile(url: url, name: name)
            }
            return
        }
        guard header["kind"] as? String == "jpeg" else { return }
        if viewingActive, let img = UIImage(data: payload) {
            viewingImage = img
        }
    }
}

// MARK: - 远程网关回调

extension AppState: WSGatewayDelegate {
    func wsDidOpen(_ ws: WSGateway) {}

    func ws(_ ws: WSGateway, didReceiveMessage msg: [String: Any]) {
        handleControl(msg, link: nil)
    }

    func ws(_ ws: WSGateway, didReceiveData data: Data) {
        guard let (header, payload) = FrameCoder.decode(data) else { return }
        handleBinary(header: header, payload: payload)
    }

    func wsDidClose(_ ws: WSGateway) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            self?.connectGateway()
        }
    }
}

// MARK: - 局域网链路回调

extension AppState: LanLinkDelegate {
    func linkDidOpen(_ link: LanLink) {
        if link.role == "initiator" {
            link.sendHandshake(role: "initiator", name: UIDevice.current.name, pf: "ios", fp: fp)
        } else {
            link.sendHandshake(role: "responder", name: UIDevice.current.name, pf: "ios", fp: fp)
        }
    }

    func link(_ link: LanLink, didControl msg: [String: Any]) {
        // 握手消息单独识别
        if msg["proto"] as? String == "cxj-link" {
            if link.role == "initiator", msg["role"] as? String == "responder" {
                var req: [String: Any] = ["t": "pair_request",
                                          "name": UIDevice.current.name, "pf": "ios", "fp": fp]
                if !loginName.isEmpty { req["account"] = loginName }
                link.sendControl(req)
            }
            link.peerName = msg["name"] as? String ?? link.peerName
            link.peerPlatform = msg["pf"] as? String ?? link.peerPlatform
            link.peerFp = msg["fp"] as? String ?? link.peerFp
            return
        }
        handleControl(msg, link: link)
    }

    func link(_ link: LanLink, didBinary header: [String: Any], payload: Data) {
        handleBinary(header: header, payload: payload)
    }

    func linkDidClose(_ link: LanLink) {
        if activeLink === link {
            activeLink = nil
            toast = "局域网连接已断开"
        }
    }
}
