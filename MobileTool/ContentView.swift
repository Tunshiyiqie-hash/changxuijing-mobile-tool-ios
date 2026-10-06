//
//  ContentView.swift
//  长须鲸手机工具
//

import SwiftUI
import UIKit
import AVFoundation
import AudioToolbox

// MARK: - 设备工具

enum DeviceTool {
    /// 机器标识符，如 iPhone13,2
    static func machineIdentifier() -> String {
        var size: Int = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }

    /// 友好型号名
    static func modelName() -> String {
        let id = machineIdentifier()
        let map: [String: String] = [
            "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12",
            "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
            "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13",
            "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus",
            "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
            "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max",
            "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus",
            "iPhone17,5": "iPhone 16e"
        ]
        return map[id] ?? id
    }

    /// 存储容量（字节）
    static func storage() -> (total: Int64, avail: Int64) {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        if let vals = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]) {
            let total = Int64(vals.volumeTotalCapacity ?? 0)
            let avail = vals.volumeAvailableCapacityForImportantUsage ?? 0
            return (total, avail)
        }
        return (0, 0)
    }

    static func gb(_ bytes: Int64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824.0)
    }
}

// MARK: - 提示音（自包含正弦波，不依赖音频文件）

final class TonePlayer {
    static let shared = TonePlayer()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var installed = false

    func play(frequency: Double = 440, duration: Double = 0.6) {
        let format = engine.outputNode.inputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }
        if !installed {
            engine.attach(player)
            engine.connect(player, to: engine.outputNode, format: format)
            installed = true
        }
        let frames = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        let channels = Int(format.channelCount)
        let total = Int(frames)
        for i in 0..<total {
            let t = Double(i) / format.sampleRate
            let fade = Double(min(i, total - i)) / 3000.0
            let env = Float(min(1, max(0, fade)))
            let v = Float(sin(2 * Double.pi * frequency * t)) * 0.25 * env
            for c in 0..<channels {
                buffer.floatChannelData?[c][i] = v
            }
        }
        buffer.frameLength = frames
        if !engine.isRunning { try? engine.start() }
        player.play()
        player.scheduleBuffer(buffer) {
            DispatchQueue.main.async { self.engine.pause() }
        }
    }
}

// MARK: - 录音（麦克风测试）

final class Recorder: NSObject {
    static let shared = Recorder()
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var hasRecording = false

    func record(status: @escaping (String) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                guard granted else { status("未授权麦克风，请在系统设置中允许") ; return }
                let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mt_rec.m4a")
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 44100,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
                ]
                do {
                    try AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: .defaultToSpeaker)
                    try AVAudioSession.sharedInstance().setActive(true)
                    self.recorder = try AVAudioRecorder(url: url, settings: settings)
                    self.recorder?.record(forDuration: 3)
                    self.hasRecording = true
                    status("正在录音（3 秒）…")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.3) {
                        status("录音完成，点击“播放录音”试听")
                    }
                } catch {
                    status("录音失败：\(error.localizedDescription)")
                }
            }
        }
    }

    func play(status: @escaping (String) -> Void) {
        guard hasRecording else { status("请先点击“开始录音”") ; return }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mt_rec.m4a")
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
            status("正在播放录音…")
        } catch {
            status("播放失败")
        }
    }
}

// MARK: - 闪光灯

func torch(on: Bool) -> String {
    guard let device = AVCaptureDevice.default(for: .video) else { return "该设备无闪光灯" }
    do {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        guard device.hasTorch else { return "该设备无闪光灯" }
        if on {
            try device.setTorchModeOn(level: 1.0)
            return "闪光灯已开启"
        } else {
            device.torchMode = .off
            return "闪光灯已关闭"
        }
    } catch {
        return "操作失败：\(error.localizedDescription)"
    }
}

// MARK: - 主页

struct ContentView: View {
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("设备信息")) {
                    InfoRow(title: "设备名称", value: UIDevice.current.name)
                    InfoRow(title: "系统版本", value: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
                    InfoRow(title: "设备型号", value: DeviceTool.modelName())
                    InfoRow(title: "设备标识符", value: UIDevice.current.identifierForVendor?.uuidString ?? "未知")
                    BatteryRow()
                }

                Section(header: Text("功能")) {
                    NavigationLink(destination: HardwareTestView()) {
                        Label("硬件检测", systemImage: "wrench.and.screwdriver")
                    }
                    NavigationLink(destination: StorageView()) {
                        Label("存储空间", systemImage: "internaldrive")
                    }
                }

                Section(header: Text("关于")) {
                    InfoRow(title: "版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    InfoRow(title: "开发者", value: "长须鲸")
                }
            }
            .navigationTitle("长须鲸手机工具")
            .listStyle(InsetGroupedListStyle())
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.gray)
                .font(.system(size: 14))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct BatteryRow: View {
    @State private var level: Float = -1
    @State private var state: UIDevice.BatteryState = .unknown

    var body: some View {
        HStack {
            Text("电池电量")
            Spacer()
            Text(text)
                .foregroundColor(.gray)
                .font(.system(size: 14))
        }
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            level = UIDevice.current.batteryLevel
            state = UIDevice.current.batteryState
        }
    }

    private var text: String {
        guard level >= 0 else { return "未知" }
        let pct = Int(level * 100)
        switch state {
        case .charging: return "\(pct)%（充电中）"
        case .full: return "100%（已充满）"
        default: return "\(pct)%"
        }
    }
}

// MARK: - 硬件检测入口

struct HardwareTestView: View {
    var body: some View {
        List {
            Section(header: Text("硬件检测")) {
                NavigationLink(destination: ScreenTestView()) { Label("屏幕坏点测试", systemImage: "rectangle.dashed") }
                NavigationLink(destination: TouchTestView()) { Label("触摸测试", systemImage: "hand.point.up") }
                NavigationLink(destination: SpeakerTestView()) { Label("扬声器测试", systemImage: "speaker.wave.2") }
                NavigationLink(destination: VibrateTestView()) { Label("振动测试", systemImage: "waveform") }
                NavigationLink(destination: TorchTestView()) { Label("闪光灯测试", systemImage: "flashlight.off.fill") }
                NavigationLink(destination: MicTestView()) { Label("麦克风测试", systemImage: "mic") }
                NavigationLink(destination: CameraTestView()) { Label("摄像头测试", systemImage: "camera") }
            }
        }
        .navigationTitle("硬件检测")
        .listStyle(InsetGroupedListStyle())
    }
}

// 通用测试页：居中状态 + 按钮
struct TestCenter<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 22) { content }
                .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: 屏幕坏点

struct ScreenTestView: View {
    private let colors: [(Color, String)] = [
        (.red, "红色"), (.green, "绿色"), (.blue, "蓝色"),
        (.white, "白色"), (.black, "黑色")
    ]
    @State private var idx = 0

    var body: some View {
        ZStack {
            colors[idx].0.ignoresSafeArea()
            VStack {
                Text("屏幕坏点测试 · \(colors[idx].1)")
                    .font(.headline)
                    .foregroundColor(darkText ? .black.opacity(0.65) : .white.opacity(0.9))
                    .padding(.top, 24)
                Spacer()
                Text(idx == colors.count - 1 ? "再点一次回到红色，左上角返回" : "点击屏幕切换颜色")
                    .font(.footnote)
                    .foregroundColor(darkText ? .black.opacity(0.55) : .white.opacity(0.75))
                    .padding(.bottom, 32)
            }
        }
        .navigationTitle("屏幕测试")
        .navigationBarTitleDisplayMode(.inline)
        .onTapGesture { idx = (idx + 1) % colors.count }
    }

    private var darkText: Bool { idx == 3 || idx == 4 }
}

// MARK: 触摸

struct TouchTestView: View {
    @State private var pts: [CGPoint] = []

    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color(uiColor: .lightGray).ignoresSafeArea()
                Canvas { ctx, _ in
                    for p in pts {
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18)),
                            with: .color(.blue)
                        )
                    }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in pts.append(v.location) }
            )
        }
        .navigationTitle("触摸测试")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("清除") { pts.removeAll() }
            }
        }
    }
}

// MARK: 扬声器

struct SpeakerTestView: View {
    @State private var status = "点击按钮播放测试音"

    var body: some View {
        TestCenter {
            Image(systemName: "speaker.wave.2.fill").font(.system(size: 56)).foregroundColor(.blue)
            Text(status).multilineTextAlignment(.center)
            Button("播放测试音") {
                status = "正在播放…"
                TonePlayer.shared.play()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { status = "播放完成，可重复点击" }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: 振动

struct VibrateTestView: View {
    @State private var status = "点击按钮，设备应振动"

    var body: some View {
        TestCenter {
            Image(systemName: "waveform").font(.system(size: 56)).foregroundColor(.blue)
            Text(status).multilineTextAlignment(.center)
            Button("触发振动") {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1.0)
                status = "已触发振动，是否感觉到？"
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: 闪光灯

struct TorchTestView: View {
    @State private var on = false
    @State private var status = "点击按钮开关闪光灯"

    var body: some View {
        TestCenter {
            Image(systemName: on ? "flashlight.on.fill" : "flashlight.off.fill")
                .font(.system(size: 56))
                .foregroundColor(on ? .yellow : .gray)
            Text(status).multilineTextAlignment(.center)
            Button(on ? "关闭闪光灯" : "开启闪光灯") {
                on.toggle()
                status = torch(on: on)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: 麦克风

struct MicTestView: View {
    @State private var status = "点击“开始录音”，对着麦克风说话"

    var body: some View {
        TestCenter {
            Image(systemName: "mic.fill").font(.system(size: 56)).foregroundColor(.blue)
            Text(status).multilineTextAlignment(.center)
            Button("开始录音") {
                Recorder.shared.record { s in status = s }
            }
            .buttonStyle(.borderedProminent)
            Button("播放录音") {
                Recorder.shared.play { s in status = s }
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: 摄像头

struct CameraPicker: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
        }
        picker.cameraDevice = .rear
        return picker
    }
    func updateUIViewController(_ ui: UIImagePickerController, context: Context) {}
}

struct CameraTestView: View {
    var body: some View {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            CameraPicker().ignoresSafeArea()
        } else {
            TestCenter {
                Image(systemName: "camera.fill").font(.system(size: 56)).foregroundColor(.gray)
                Text("当前设备不可用摄像头")
            }
        }
    }
}

// MARK: - 存储空间

struct StorageView: View {
    var body: some View {
        let s = DeviceTool.storage()
        let used = s.total - s.avail
        let fraction = s.total > 0 ? Double(used) / Double(s.total) : 0
        List {
            Section(header: Text("存储空间")) {
                InfoRow(title: "总容量", value: DeviceTool.gb(s.total))
                InfoRow(title: "已用容量", value: DeviceTool.gb(used))
                InfoRow(title: "可用容量", value: DeviceTool.gb(s.avail))
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(.blue)
                    .padding(.vertical, 4)
            }
        }
        .navigationTitle("存储空间")
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
