//
//  FileTransfer.swift
//  长须鲸手机工具 - 文件收发工具集
//  · 局域网：NWConnection 分块（256KB）+ sha256 校验（协议 §3.5）
//  · 远程：经服务器 relay 中转（APIClient.relayPut/Get/Ack）
//  · 落盘：UIDocumentPicker 选文件 / UIActivityViewController 分享 / 相册保存
//

import Foundation
import CommonCrypto
import UIKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - SHA256

enum FileHash {
    static func sha256Hex(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buf in
            _ = CC_SHA256(buf.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - 局域网接收收据

struct FileReceipt {
    let name: String
    let size: Int64
    let sha256: String
    var data: Data = Data()
    var lastSeq: Int = -1
    var finished: Bool = false
}

final class LanFileReceiver {
    static let shared = LanFileReceiver()
    private var receipts: [String: FileReceipt] = [:]

    /// 处理一个二进制 file 分块；完成且校验通过后返回临时文件 URL。
    func addChunk(header: [String: Any], payload: Data) -> URL? {
        guard let sid = header["sid"] as? String else { return nil }
        let name = header["name"] as? String ?? "未命名文件"
        let size = (header["size"] as? Int64) ?? Int64(payload.count)
        let sha = header["sha256"] as? String ?? ""
        let seq = (header["seq"] as? Int) ?? 0
        let last = header["last"] as? Bool ?? false

        var r = receipts[sid] ?? FileReceipt(name: name, size: size, sha256: sha)
        r.data.append(payload)
        r.lastSeq = seq
        if last { r.finished = true }
        receipts[sid] = r

        guard r.finished else { return nil }
        defer { receipts.removeValue(forKey: sid) }

        // 校验 sha256
        if !r.sha256.isEmpty, FileHash.sha256Hex(r.data) != r.sha256 {
            return nil
        }
        let dir = NSTemporaryDirectory()
        let url = URL(fileURLWithPath: dir).appendingPathComponent("cxj_recv_\(sid)_\(name)")
        try? r.data.write(to: url, options: .atomic)
        return url
    }
}

// MARK: - 局域网发送（分块）

enum FileSender {
    /// 在已配对的局域网链路上分块发送整个文件。
    static func sendChunks(data: Data, name: String, sid: String, sha256: String,
                           over link: LanLink, onDone: @escaping () -> Void) {
        let total = data.count
        var offset = 0
        var seq = 0
        func step() {
            let end = min(offset + Config.fileChunkSize, total)
            let chunk = data.subdata(in: offset..<end)
            let last = end == total
            let header: [String: Any] = [
                "t": "file", "sid": sid, "seq": seq,
                "name": name, "size": total, "sha256": sha256, "last": last
            ]
            link.sendBinary(header: header, payload: chunk)
            offset = end
            seq += 1
            if !last {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.004) { step() }
            } else {
                onDone()
            }
        }
        step()
    }
}

// MARK: - 文件选择器（发送方选本地文件）

struct FilePicker: UIViewControllerRepresentable {
    /// 选中文件后的回调（临时拷贝 URL）
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        } else {
            picker = UIDocumentPickerViewController(documentTypes: ["public.item"], in: .open)
        }
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: FilePicker
        init(_ parent: FilePicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.onPick(url)
        }
    }
}

// MARK: - 系统分享面板（接收方落盘）

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onComplete: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, _, _, _ in self.onComplete?() }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - 相册保存

enum PhotoSaver {
    static func save(image: UIImage, completion: @escaping (Bool) -> Void) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        completion(true)
    }
}
