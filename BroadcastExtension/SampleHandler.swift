//
//  SampleHandler.swift
//  长须鲸屏幕广播 - ReplayKit Broadcast Upload Extension
//  取 CMSampleBuffer → 缩放最长边 ≤1280 / JPEG q35 / 12fps，经 App Group 共享 token，
//  用 URLSessionWebSocketTask 直连网关推 JPEG 二进制帧（主 App 挂起时扩展独立运行）。
//  协议 §3.3：二进制帧 [4BE 头长][JSON 头][负载]，头 {t:"v", sid, seq, kind:"jpeg", w, h, ts}
//

import ReplayKit
import CoreMedia
import CoreImage
import Foundation

class SampleHandler: RPBroadcastSampleHandler {

    private var gateway: WSGateway?
    private let ciContext = CIContext()
    private let sid = Config.makeSid()
    private var seq: Int = 0
    private var lastFrameTime: TimeInterval = 0

    // MARK: 生命周期
    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        // 从 App Group 共享容器读取设备令牌（主 App 登录注册后写入）
        let token = GroupDefaults.get("device_token") ?? KeychainStore.get("device_token") ?? ""
        guard !token.isEmpty else {
            let err = NSError(domain: "cxj.broadcast", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "缺少设备令牌，请先在主 App 登录"])
            finishBroadcastWithError(err)
            return
        }
        let ws = WSGateway(deviceToken: token)
        ws.connect()
        gateway = ws
        seq = 0
        lastFrameTime = 0
    }

    override func broadcastFinished() {
        gateway?.disconnect()
        gateway = nil
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                      with sampleBufferType: RPSampleBufferType) {
        // 仅处理视频帧；麦克风已在主 App 关闭
        guard sampleBufferType == .video else { return }

        // 12fps 节流：丢弃过期帧
        let now = Date().timeIntervalSince1970
        guard now - lastFrameTime >= 1.0 / Config.targetFps else { return }
        lastFrameTime = now

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        var ciImage = CIImage(cvImageBuffer: imageBuffer)

        // 最长边缩到 ≤1280
        let extent = ciImage.extent
        let maxEdge = max(extent.width, extent.height)
        if maxEdge > Config.jpegMaxEdge {
            let scale = Config.jpegMaxEdge / maxEdge
            ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        let qualityKey = CIContextOption(rawValue: kCICompressionQuality as String)
        guard let jpeg = ciContext.jpegRepresentation(
            of: ciImage,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            options: [qualityKey: Config.jpegQuality]
        ) else { return }

        let frameExtent = ciImage.extent
        let header: [String: Any] = [
            "t": "v",
            "sid": sid,
            "seq": seq,
            "kind": "jpeg",
            "w": Int(frameExtent.width),
            "h": Int(frameExtent.height),
            "ts": Int64(now * 1000)
        ]
        seq += 1
        gateway?.send(data: FrameCoder.encode(header: header, payload: jpeg))
    }
}
