//
//  FrameCoder.swift
//  长须鲸手机工具 - 二进制帧封装：[4 字节大端头长 N][N 字节 JSON 头][负载]
//

import Foundation

enum FrameCoder {
    static func encode(header: [String: Any], payload: Data) -> Data {
        let h: Data
        do {
            h = try JSONSerialization.data(withJSONObject: header, options: [])
        } catch {
            return Data()
        }
        var len = UInt32(h.count).bigEndian
        var out = Data()
        withUnsafeBytes(of: &len) { buf in
            out.append(contentsOf: buf)
        }
        out.append(h)
        out.append(payload)
        return out
    }

    /// 解析一整帧（WS 单条二进制消息即一帧）。返回 (header, payload)。
    static func decode(_ data: Data) -> ([String: Any], Data)? {
        guard data.count >= 4 else { return nil }
        let n = Int(UInt32(data[0]) << 24 | UInt32(data[1]) << 16 |
                    UInt32(data[2]) << 8 | UInt32(data[3]))
        guard data.count >= 4 + n else { return nil }
        let headerData = data.subdata(in: 4..<(4 + n))
        let payload = data.subdata(in: (4 + n)..<data.count)
        guard let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any] else {
            return nil
        }
        return (header, payload)
    }
}
