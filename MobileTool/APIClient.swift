//
//  APIClient.swift
//  长须鲸手机工具 - 账号/安全码/设备/中继 REST 客户端
//

import Foundation

enum APIError: Error {
    case http(Int, String)
    case badResponse
    case network(Error)
}

struct RemoteDevice: Identifiable {
    let deviceId: String
    let name: String
    let platform: String
    let online: Bool
    let lastSeen: TimeInterval?
    var id: String { deviceId }
}

final class APIClient {
    static let shared = APIClient()
    private init() {}

    private(set) var userToken: String? = KeychainStore.get("user_token")
    private(set) var deviceToken: String? = KeychainStore.get("device_token")
    private(set) var deviceId: String? = KeychainStore.get("device_id")
    private(set) var loginName: String? = KeychainStore.get("login_name")
    private(set) var codeSet: Bool = KeychainStore.get("code_set") == "1"

    func setUserToken(_ t: String?) {
        userToken = t
        if let t = t { KeychainStore.set("user_token", t) } else { KeychainStore.delete("user_token") }
    }
    func setDeviceToken(_ t: String?) {
        deviceToken = t
        if let t = t { KeychainStore.set("device_token", t) } else { KeychainStore.delete("device_token") }
        GroupDefaults.set("device_token", t ?? "")
    }
    func setDeviceId(_ id: String?) {
        deviceId = id
        if let id = id { KeychainStore.set("device_id", id) } else { KeychainStore.delete("device_id") }
    }
    func setLoginName(_ n: String?) {
        loginName = n
        if let n = n { KeychainStore.set("login_name", n) } else { KeychainStore.delete("login_name") }
    }
    func setCodeSet(_ v: Bool) {
        codeSet = v
        KeychainStore.set("code_set", v ? "1" : "0")
    }

    // MARK: - 通用 JSON 请求
    @discardableResult
    private func request(path: String,
                         method: String,
                         body: [String: Any]?,
                         auth: String?,
                         completion: @escaping (Result<[String: Any], APIError>) -> Void) -> URLSessionDataTask {
        let url = URL(string: Config.restBase + path)!
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let auth = auth { req.setValue("Bearer \(auth)", forHTTPHeaderField: "Authorization") }
        if let body = body { req.httpBody = try? JSONSerialization.data(withJSONObject: body) }
        let task = URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err {
                DispatchQueue.main.async { completion(.failure(.network(err))) }
                return
            }
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async { completion(.failure(.badResponse)) }
                return
            }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 200
            if let ok = obj["ok"] as? Bool, !ok {
                DispatchQueue.main.async { completion(.failure(.http(code, (obj["error"] as? String) ?? "未知错误"))) }
            } else {
                DispatchQueue.main.async { completion(.success(obj)) }
            }
        }
        task.resume()
        return task
    }

    // MARK: - 账号
    func register(login: String, password: String, completion: @escaping (Result<String, APIError>) -> Void) {
        request(path: "/api/register", method: "POST", body: ["login": login, "password": password], auth: nil) { r in
            switch r {
            case .success(let obj):
                if let t = obj["token"] as? String { completion(.success(t)) }
                else { completion(.failure(.badResponse)) }
            case .failure(let e): completion(.failure(e))
            }
        }
    }

    func login(login: String, password: String, completion: @escaping (Result<(token: String, codeSet: Bool), APIError>) -> Void) {
        request(path: "/api/login", method: "POST", body: ["login": login, "password": password], auth: nil) { r in
            switch r {
            case .success(let obj):
                if let t = obj["token"] as? String {
                    completion(.success((t, obj["code_set"] as? Bool ?? false)))
                } else { completion(.failure(.badResponse)) }
            case .failure(let e): completion(.failure(e))
            }
        }
    }

    func logout(completion: @escaping () -> Void) {
        request(path: "/api/logout", method: "POST", body: [:], auth: userToken) { _ in
            DispatchQueue.main.async { completion() }
        }
    }

    func me(completion: @escaping (Result<[RemoteDevice], APIError>) -> Void) {
        guard let token = userToken else { completion(.failure(.badResponse)); return }
        request(path: "/api/me", method: "GET", body: nil, auth: token) { r in
            switch r {
            case .success(let obj):
                let arr = (obj["devices"] as? [[String: Any]]) ?? []
                let ds = arr.map { d -> RemoteDevice in
                    RemoteDevice(deviceId: (d["device_id"] as? String) ?? "",
                                 name: (d["name"] as? String) ?? "未知",
                                 platform: (d["platform"] as? String) ?? "ios",
                                 online: (d["online"] as? Bool) ?? false,
                                 lastSeen: (d["last_seen"] as? TimeInterval))
                }
                completion(.success(ds))
            case .failure(let e): completion(.failure(e))
            }
        }
    }

    // MARK: - 安全码
    func setCode(_ code: String, oldCode: String? = nil, completion: @escaping (Result<Void, APIError>) -> Void) {
        guard let token = userToken else { completion(.failure(.badResponse)); return }
        var body: [String: Any] = ["code": code]
        if let old = oldCode { body["old_code"] = old }
        request(path: "/api/security/set-code", method: "POST", body: body, auth: token) { r in
            switch r {
            case .success: completion(.success(()))
            case .failure(let e): completion(.failure(e))
            }
        }
    }

    func verifyCode(_ code: String, completion: @escaping (Result<Bool, APIError>) -> Void) {
        guard let token = userToken else { completion(.success(false)); return }
        request(path: "/api/security/verify", method: "POST", body: ["code": code], auth: token) { r in
            switch r {
            case .success(let obj): completion(.success(obj["ok"] as? Bool ?? false))
            case .failure: completion(.success(false))
            }
        }
    }

    // MARK: - 设备
    func registerDevice(name: String, fp: String, completion: @escaping (Result<(deviceId: String, deviceToken: String), APIError>) -> Void) {
        guard let token = userToken else { completion(.failure(.badResponse)); return }
        request(path: "/api/device/register", method: "POST",
                body: ["name": name, "platform": "ios", "fp": fp], auth: token) { r in
            switch r {
            case .success(let obj):
                if let did = obj["device_id"] as? String, let dt = obj["device_token"] as? String {
                    completion(.success((did, dt)))
                } else { completion(.failure(.badResponse)) }
            case .failure(let e): completion(.failure(e))
            }
        }
    }

    func deleteDevice(_ deviceId: String, completion: @escaping (Result<Void, APIError>) -> Void) {
        guard let token = userToken else { completion(.failure(.badResponse)); return }
        request(path: "/api/device/delete", method: "POST", body: ["device_id": deviceId], auth: token) { r in
            switch r {
            case .success: completion(.success(()))
            case .failure(let e): completion(.failure(e))
            }
        }
    }

    func resolvePeer(account: String, code: String, completion: @escaping (Result<String, APIError>) -> Void) {
        guard let token = userToken else { completion(.failure(.badResponse)); return }
        request(path: "/api/peer/resolve", method: "POST", body: ["account": account, "code": code], auth: token) { r in
            switch r {
            case .success(let obj):
                if let ticket = obj["ticket"] as? String { completion(.success(ticket)) }
                else { completion(.failure(.badResponse)) }
            case .failure(let e): completion(.failure(e))
            }
        }
    }

    // MARK: - 远程中继（MinIO 中转，单文件 ≤ 95MB）
    func relayPut(sid: String, data: Data, completion: @escaping (Result<Void, APIError>) -> Void) {
        guard let dt = deviceToken else { completion(.failure(.badResponse)); return }
        let url = URL(string: Config.restBase + "/api/relay/put/\(sid)")!
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(dt)", forHTTPHeaderField: "Authorization")
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        let task = URLSession.shared.dataTask(with: req) { _, resp, err in
            if let err = err { DispatchQueue.main.async { completion(.failure(.network(err))) }; return }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 200
            if code >= 400 { DispatchQueue.main.async { completion(.failure(.http(code, "中继上传失败"))) }; return }
            DispatchQueue.main.async { completion(.success(())) }
        }
        task.resume()
    }

    func relayGet(sid: String, completion: @escaping (Result<Data, APIError>) -> Void) {
        guard let dt = deviceToken else { completion(.failure(.badResponse)); return }
        let url = URL(string: Config.restBase + "/api/relay/get/\(sid)")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(dt)", forHTTPHeaderField: "Authorization")
        let task = URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err { DispatchQueue.main.async { completion(.failure(.network(err))) }; return }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 200
            guard let data = data, code < 400 else {
                DispatchQueue.main.async { completion(.failure(.http(code, "中继下载失败"))) }; return
            }
            DispatchQueue.main.async { completion(.success(data)) }
        }
        task.resume()
    }

    func relayAck(sid: String, completion: @escaping () -> Void) {
        request(path: "/api/relay/ack/\(sid)", method: "POST", body: [:], auth: deviceToken) { _ in
            DispatchQueue.main.async { completion() }
        }
    }

    func relayAbort(sid: String, completion: @escaping () -> Void) {
        request(path: "/api/relay/abort/\(sid)", method: "POST", body: [:], auth: deviceToken) { _ in
            DispatchQueue.main.async { completion() }
        }
    }
}
