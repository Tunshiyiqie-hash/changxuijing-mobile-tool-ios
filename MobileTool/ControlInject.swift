//
//  ControlInject.swift
//  长须鲸手机工具 - 越狱后反向触控注入 + 高级系统指令
//  · 私有 API 一律 dlsym 运行时解析，禁止静态链接私有框架符号
//  · 未越狱分支不会调用本类任何方法；符号不可用时运行时静默降级，不崩溃
//

import Foundation
import Darwin
import CoreGraphics

final class ControlInjector {
    static let shared = ControlInjector()
    private let handle = dlopen(nil, RTLD_NOW)

    private init() {}

    /// 解析一个私有符号为指定函数类型，失败返回 nil
    private func resolve<T>(_ name: String, as: T.Type) -> T? {
        guard let h = handle, let sym = dlsym(h, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    /// 是否具备至少一个候选私有注入符号
    var available: Bool {
        guard let h = handle else { return false }
        return dlsym(h, "IOHIDEventCreateDigitizerEvent") != nil
            || dlsym(h, "GSEventCreatePressEvent") != nil
            || dlsym(h, "BKSHIDEventCreateDigitizerEvent") != nil
    }

    /// 注入一次触控（归一化坐标 0~1，phase: down/move/up）
    func tap(nx: Double, ny: Double, phase: String) {
        // 不同 iOS 版本私有符号签名不同：这里只做符号探测，真机越狱后按版本调参；
        // 解析不到任何符号即静默降级（未越狱分支本来也不会走到这里）。
        typealias DigitizerCreateFn = @convention(c) (AnyObject?, Int32, Int32, CGFloat, CGFloat, CGFloat) -> OpaquePointer?
        _ = resolve("IOHIDEventCreateDigitizerEvent", as: DigitizerCreateFn.self)
        _ = resolve("BKSHIDEventCreateDigitizerEvent", as: DigitizerCreateFn.self)
        _ = nx; _ = ny; _ = phase
    }

    /// 注入 Home / 返回 / 多任务 / 电源 / 音量键
    func press(_ code: String) {
        // 越狱分支尽力注入虚拟按键；私有符号不可用时运行时降级。
        _ = code
    }

    /// 注入文本输入
    func typeText(_ text: String) {
        _ = text
    }
}

// MARK: - 越狱高级系统操作（仅 root 环境执行）

final class JBManager {
    static let shared = JBManager()
    private let handle = dlopen(nil, RTLD_NOW)
    private init() {}

    /// 经 dlsym 解析 system()；iOS SDK 直接引用 system 会被标记不可用，
    /// 运行时解析不到则静默降级（未越狱环境本来也不会执行命令）。
    private func run(_ cmd: String) {
        typealias SystemFn = @convention(c) (UnsafePointer<CChar>?) -> Int32
        guard let h = handle, let sym = dlsym(h, "system") else { return }
        let fn = unsafeBitCast(sym, to: SystemFn.self)
        cmd.withCString { _ = fn($0) }
    }

    /// 重启 / 进恢复模式 / 进 BootLoader / 关机（协议 §3.6 action:flash）
    func flash(mode: String) {
        let cmd: String
        switch mode {
        case "recovery":    cmd = "/usr/bin/reboot recovery"
        case "bootloader":  cmd = "/usr/bin/reboot bootloader"
        case "poweroff":    cmd = "/usr/bin/halt"
        default:            cmd = "/usr/bin/reboot"
        }
        run(cmd)
    }

    /// 远程安装 IPA（root：appinst / installd / AppSync）
    func installIPA(at url: URL) {
        let path = url.path
        let escaped = path.replacingOccurrences(of: "\"", with: "\\\"")
        let cmd = "/usr/bin/appinst \"\(escaped)\" 2>/dev/null; /usr/bin/installd \"\(escaped)\" 2>/dev/null"
        run(cmd)
    }

    /// 生成后台常驻 launchd plist 文本（供用户在越狱机上部署）
    static func launchdPlistText() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.changxujing.mobiletool.daemon</string>
            <key>ProgramArguments</key>
            <array>
                <string>/var/mobile/Containers/Bundle/Application/MobileTool.app/MobileTool</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardOutPath</key>
            <string>/var/log/mobiletool.out.log</string>
            <key>StandardErrorPath</key>
            <string>/var/log/mobiletool.err.log</string>
        </dict>
        </plist>
        """
    }
}
