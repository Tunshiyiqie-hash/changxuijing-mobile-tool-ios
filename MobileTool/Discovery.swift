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

    // MARK: - 开关
    func start() {
        guard listener == nil, browser == nil else { return }
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

    // MARK: - 被发现：注册 Bonjour 服务 + TXT
    private func startListener() {
        let acct = AppState.shared.loginName
        let txt = NWTXTRecord([
            "v": "1",
            "name": ownName,
            "pf": "ios",
            "fp": ownFp,
            "acct": acct
        ])
        guard let lw = try? NWListener(using: .tcp) else { return }
        lw.service = NWListener.Service(name: ownFp,
                                        type: Config.bonjourType,
                                        domain: Config.bonjourDomain,
                                        txtRecord: txt)
        lw.stateUpdateHandler = { _ in }
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
        b.browseResultsChangedHandler = { [weak self] (results: Set<NWBrowser.Result>,
                                                       _ change: NWBrowser.Result.Change) in
            guard let self = self else { return }
            var list: [Peer] = []
            for r in results {
                guard case let .service(name, _, _) = r.endpoint else { continue }
                var fp = name
                var pf = "ios"
                var acct = ""
                var peerName = name
                if case let .bonjour(txt) = r.metadata {
                    fp = txt["fp"] ?? name
                    pf = txt["pf"] ?? "ios"
                    acct = txt["acct"] ?? ""
                    peerName = txt["name"] ?? name
                }
                list.append(Peer(id: fp, name: peerName, fp: fp, platform: pf,
                                 account: acct, endpoint: r.endpoint,
                                 isSelf: fp == self.ownFp))
            }
            DispatchQueue.main.async { self.peers = list }
        }
        b.start(queue: browserQueue)
        browser = b
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
