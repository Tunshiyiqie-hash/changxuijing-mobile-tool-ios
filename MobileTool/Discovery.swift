//
//  Discovery.swift
//  长须鲸手机工具 - Bonjour 双向发现（_cxjdev._tcp）
//  ① NWListener 注册服务被电脑/其他手机发现，发布 TXT：v/name/pf/fp/port/acct
//  ② NWBrowser 浏览局域网内其他设备并在 UI 列出“附近电脑/附近设备”
//  ③ iPhone 可主动点选某台设备发起配对（AppState 内建 LanLink 完成 pair_request/pair_result）
//

import Foundation
import UIKit
import Network

struct Peer: Identifiable {
    let id: String            // fp（去重键）
    let name: String
    let fp: String
    let platform: String      // win | android | ios
    let account: String
    let endpoint: NWEndpoint?
    let isSelf: Bool

    var displayName: String { name.isEmpty ? fp : name }
}

final class Discovery: NSObject, ObservableObject {
    static let shared = Discovery()

    @Published var peers: [Peer] = []
    @Published var pairStatus: [String: String] = [:]  // fp -> waiting / connected / rejected

    private var listener: NWListener?
    private var browser: NWBrowser?
    private let listenerQueue = DispatchQueue(label: "cxj.listener")
    private let browserQueue = DispatchQueue(label: "cxj.browser")

    weak var app: AppState?

    private let ownFp: String
    private let ownName: String

    private override init() {
        ownFp = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        ownName = UIDevice.current.name
        super.init()
    }

    // MARK: - 允许被发现开关（协议 §2.1，默认开；离线模式另由 AppState 拦截）
    static let enabledKey = "discovery_enabled"
    static func isEnabled() -> Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }
    static func setEnabled(_ v: Bool) {
        UserDefaults.standard.set(v, forKey: enabledKey)
    }

    // MARK: - 开关
    func start() {
        guard Discovery.isEnabled(), listener == nil, browser == nil else { return }
        startListener()
        startBrowser()
    }

    func stop() {
        listener?.cancel()
        browser?.cancel()
        listener = nil
        browser = nil
        peers = []
    }

    // MARK: - 被发现：注册 Bonjour 服务 + TXT（v/name/pf/fp/port/acct，协议 §2.1）
    private func makeTxt(port: UInt16) -> NWTXTRecord {
        NWTXTRecord([
            "v": "1",
            "name": ownName,
            "pf": "ios",
            "fp": ownFp,
            "port": String(port),
            "acct": AppState.shared.loginName
        ])
    }

    private func startListener() {
        guard let lw = try? NWListener(using: .tcp) else { return }
        lw.service = NWListener.Service(name: ownFp,
                                        type: Config.bonjourType,
                                        domain: Config.bonjourDomain,
                                        txtRecord: makeTxt(port: 0))
        lw.stateUpdateHandler = { state in
            // 端口就绪后回填真实监听端口到 TXT 记录
            if case .ready = state, let port = lw.port?.rawValue {
                lw.service?.txtRecord = self.makeTxt(port: port)
            }
        }
        lw.newConnectionHandler = { [weak self] connection in
            guard let self = self else { return }
            let link = LanLink(accepted: connection)
            link.role = "responder"
            self.app?.handleIncomingLink(link)
        }
        lw.start(queue: listenerQueue)
        listener = lw
    }

    // MARK: - 发现别人：浏览 TXT 记录
    private func startBrowser() {
        let desc = NWBrowser.Descriptor.bonjourWithTXTRecord(type: Config.bonjourType,
                                                              domain: Config.bonjourDomain)
        let b = NWBrowser(for: desc, using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self = self else { return }
            let list: [Peer] = results.compactMap { self.mapPeer($0) }
            DispatchQueue.main.async { self.peers = list }
        }
        b.start(queue: browserQueue)
        browser = b
    }

    /// 把一条浏览结果解析成 Peer（独立方法，避免闭包内类型推断过载）
    private func mapPeer(_ result: NWBrowser.Result) -> Peer? {
        let endpoint: NWEndpoint = result.endpoint
        var name: String = "未知设备"
        switch endpoint {
        case NWEndpoint.service(let n, _, _, _):
            name = n
        default:
            return nil
        }
        var fp: String = name
        var pf: String = "ios"
        var acct: String = ""
        var peerName: String = name
        let meta: NWBrowser.Result.Metadata = result.metadata
        switch meta {
        case NWBrowser.Result.Metadata.bonjour(let txt):
            if let v: String = txt["fp"] { fp = v }
            if let v: String = txt["pf"] { pf = v }
            if let v: String = txt["acct"] { acct = v }
            if let v: String = txt["name"] { peerName = v }
        default:
            break
        }
        return Peer(id: fp, name: peerName, fp: fp, platform: pf,
                    account: acct, endpoint: endpoint, isSelf: fp == ownFp)
    }

    // MARK: - 主动发起配对
    func pair(_ peer: Peer) {
        guard let ep = peer.endpoint else {
            app?.toast = "无法解析该设备地址"
            return
        }
        pairStatus[peer.id] = "waiting"
        let link = LanLink(to: ep)
        link.role = "initiator"
        link.peerFp = peer.fp
        link.peerName = peer.name
        link.peerPlatform = peer.platform
        link.peerAccount = peer.account
        app?.beginOutgoingPair(link, peer: peer)
    }

    // MARK: - 信任列表（持久化）
    static func trustedSet() -> Set<String> {
        let arr = UserDefaults.standard.stringArray(forKey: Config.trustKey) ?? []
        return Set(arr)
    }

    func isTrusted(_ fp: String) -> Bool {
        Discovery.trustedSet().contains(fp)
    }

    func trust(_ fp: String) {
        var arr = UserDefaults.standard.stringArray(forKey: Config.trustKey) ?? []
        if !arr.contains(fp) { arr.append(fp) }
        UserDefaults.standard.set(arr, forKey: Config.trustKey)
    }

    func untrust(_ fp: String) {
        let arr = (UserDefaults.standard.stringArray(forKey: Config.trustKey) ?? [])
            .filter { $0 != fp }
        UserDefaults.standard.set(arr, forKey: Config.trustKey)
    }
}
