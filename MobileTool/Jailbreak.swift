//
//  Jailbreak.swift
//  长须鲸手机工具 - 越狱检测（运行时多信号，命中 >=2 判越狱）
//  仅做只读探测，不执行任何越狱动作；未越狱分支不会调用任何私有 API。
//

import Foundation
import UIKit

final class Jailbreak {
    static let shared = Jailbreak()

    /// 命中信号数（便于在“我的”页面展示诊断）
    let signalCount: Int
    let isJailbroken: Bool

    private init() {
        var hits = 0

        // 1. 常见越狱文件 / 目录
        let paths = [
            "/Applications/Cydia.app",
            "/Applications/Sileo.app",
            "/Applications/Zebra.app",
            "/private/var/lib/apt",
            "/private/var/stash",
            "/private/var/cache/apt",
            "/bin/bash",
            "/bin/sh",
            "/usr/sbin/sshd",
            "/usr/libexec/cydia",
            "/Library/MobileSubstrate",
            "/private/jailbreak"
        ]
        for p in paths where FileManager.default.fileExists(atPath: p) {
            hits += 1
        }

        // 2. 越狱 URL Scheme 可打开
        for scheme in ["cydia://", "sileo://", "zbra://"] {
            if let url = URL(string: scheme), UIApplication.shared.canOpenURL(url) {
                hits += 1
                break
            }
        }

        // 3. 能否向沙盒外写文件
        let testPath = "/private/jailbreak_test_\(UUID().uuidString).txt"
        do {
            try "test".write(toFile: testPath, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: testPath)
            hits += 1
        } catch {}

        // 4. 读取 /etc/hosts 是否存在额外条目（越狱机常被注入）
        if let hosts = try? String(contentsOfFile: "/etc/hosts", encoding: .utf8),
           hosts.components(separatedBy: .newlines).count > 2 {
            hits += 1
        }

        self.signalCount = hits
        self.isJailbroken = hits >= 2
    }
}
