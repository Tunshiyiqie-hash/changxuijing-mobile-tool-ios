//
//  KeychainStore.swift
//  长须鲸手机工具 - 轻量 Keychain 封装
//

import Foundation
import Security

enum KeychainStore {
    private static func query(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.changxujing.mobiletool",
            kSecAttrAccount as String: key
        ]
    }

    static func set(_ key: String, _ value: String) {
        var q = query(key)
        SecItemDelete(q as CFDictionary)
        q[kSecValueData as String] = value.data(using: .utf8) ?? Data()
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        SecItemDelete(query(key) as CFDictionary)
    }
}

/// App Group 共享 UserDefaults（主 App <-> 广播扩展）
enum GroupDefaults {
    static var shared: UserDefaults? {
        UserDefaults(suiteName: Config.appGroup)
    }

    static func set(_ key: String, _ value: String) {
        shared?.set(value, forKey: key)
    }
    static func get(_ key: String) -> String? {
        shared?.string(forKey: key)
    }
}
