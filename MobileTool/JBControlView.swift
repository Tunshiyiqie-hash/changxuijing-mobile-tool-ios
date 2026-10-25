//
//  JBControlView.swift
//  长须鲸手机工具 - 越狱高级功能入口（仅越狱后显示，协议 §3.6 / §5）
//

import SwiftUI

struct JBControlView: View {
    @EnvironmentObject var app: AppState
    @State private var status = ControlInjector.shared.available
        ? "触控注入：候选私有符号已解析"
        : "触控注入：部分私有符号不可用，运行时已降级"
    @State private var showingPlist = false
    @State private var showingIpa = false
    @State private var plistURL: URL?
    @State private var confirmReboot: String?

    var body: some View {
        List {
            Section("反向触控注入") {
                Text(status).font(.footnote).foregroundColor(.secondary)
                Button("测试点击屏幕中心") {
                    ControlInjector.shared.tap(nx: 0.5, ny: 0.5, phase: "down")
                }
                Button("测试 Home 键") {
                    ControlInjector.shared.press("home")
                }
            }

            Section("后台常驻") {
                Text("越狱后可部署 launchd plist 实现后台常驻；未越狱仅能依靠广播扩展保活。")
                    .font(.footnote).foregroundColor(.secondary)
                Button("生成 launchd plist 并分享") {
                    let text = JBManager.launchdPlistText()
                    let url = URL(fileURLWithPath: NSTemporaryDirectory())
                        .appendingPathComponent("com.changxujing.mobiletool.daemon.plist")
                    try? text.write(to: url, atomically: true, encoding: .utf8)
                    plistURL = url
                    showingPlist = true
                }
            }

            Section("远程安装 IPA") {
                Text("对方推送 IPA 后，root 身份调用 appinst / installd 静默安装；未越狱设备不可用。")
                    .font(.footnote).foregroundColor(.secondary)
                Button("选择本机 IPA 安装") { showingIpa = true }
            }

            Section("重启 / 恢复模式（高风险）") {
                Button("重启设备") { confirmReboot = "restart" }
                Button("进入恢复模式") { confirmReboot = "recovery" }
                Button("关机") { confirmReboot = "poweroff" }
            }
        }
        .navigationTitle("越狱高级功能")
        .sheet(isPresented: $showingPlist) {
            if let u = plistURL { ShareSheet(items: [u]) }
        }
        .sheet(isPresented: $showingIpa) {
            FilePicker { url in
                JBManager.shared.installIPA(at: url)
                app.toast = "已提交本机 IPA 安装指令"
            }
        }
        .alert("确认操作？",
               isPresented: Binding(get: { confirmReboot != nil },
                                    set: { if !$0 { confirmReboot = nil } })) {
            Button("取消", role: .cancel) { confirmReboot = nil }
            Button("确认", role: .destructive) {
                if let mode = confirmReboot { JBManager.shared.flash(mode: mode) }
                confirmReboot = nil
            }
        } message: {
            Text("该操作需要越狱 root 权限，执行后设备将立即响应。")
        }
    }
}
