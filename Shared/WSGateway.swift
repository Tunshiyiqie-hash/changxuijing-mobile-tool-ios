//
//  WSGateway.swift
//  长须鲸手机工具 - 远程网关 WebSocket（主 App 与广播扩展共用）
//  wss://changxvjing.com/ws/?dt=<device_token>
//

import Foundation

protocol WSGatewayDelegate: AnyObject {
    func wsDidOpen(_ ws: WSGateway)
    func ws(_ ws: WSGateway, didReceiveMessage msg: [String: Any])
    func ws(_ ws: WSGateway, didReceiveData data: Data)
    func wsDidClose(_ ws: WSGateway)
}

final class WSGateway: NSObject, URLSessionWebSocketDelegate {
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private let deviceToken: String
    private var pingTimer: Timer?
    weak var delegate: WSGatewayDelegate?

    init(deviceToken: String) {
        self.deviceToken = deviceToken
        super.init()
    }

    func connect() {
        var comp = URLComponents(string: Config.wsBase)
        comp?.queryItems = [URLQueryItem(name: "dt", value: deviceToken)]
        guard let url = comp?.url else { return }
        let s = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        session = s
        let t = s.webSocketTask(with: url)
        task = t
        t.resume()
        startReceive()
        startPing()
    }

    func disconnect() {
        pingTimer?.invalidate()
        task?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
    }

    private func startPing() {
        pingTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.send(json: ["t": "ping"])
        }
    }

    private func startReceive() {
        task?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    if let d = text.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                        self.delegate?.ws(self, didReceiveMessage: obj)
                    }
                case .data(let d):
                    self.delegate?.ws(self, didReceiveData: d)
                @unknown default:
                    break
                }
                self.startReceive()
            case .failure:
                self.delegate?.wsDidClose(self)
            }
        }
    }

    func send(json: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: json),
              let s = String(data: d, encoding: .utf8) else { return }
        task?.send(.string(s)) { _ in }
    }

    func send(data: Data) {
        task?.send(.data(data)) { _ in }
    }

    // MARK: URLSessionWebSocketDelegate
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        delegate?.wsDidOpen(self)
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        delegate?.wsDidClose(self)
    }
}
