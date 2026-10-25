//
//  Config.swift
//  长须鲸手机工具 - 全局常量（主 App 与广播扩展共享）
//

import Foundation
import CoreGraphics

enum Config {
    /// REST 基址
    static let restBase = "https://changxvjing.com"
    /// 远程网关 WebSocket
    static let wsBase = "wss://changxvjing.com/ws/"
    /// App Group 共享容器
    static let appGroup = "group.com.changxujing.mobiletool.share"
    /// Bonjour 服务类型
    static let bonjourType = "_cxjdev._tcp"
    static let bonjourDomain = "local."

    /// 屏幕帧参数（协议 v1 统一）
    static let jpegMaxEdge: CGFloat = 1280
    static let jpegQuality: CGFloat = 0.35
    static let targetFps: Double = 12.0

    /// 局域网文件分块大小（256KB，协议 §3.5）
    static let fileChunkSize: Int = 256 * 1024

    /// 已信任设备指纹持久化键
    static let trustKey = "trust_fps"

    /// 生成本地 sid：cxj-<13位时间戳>-<6位随机>
    static func makeSid() -> String {
        let ts = Int64(Date().timeIntervalSince1970 * 1000)
        let rand = Int.random(in: 100000...999999)
        return "cxj-\(ts)-\(rand)"
    }
}
