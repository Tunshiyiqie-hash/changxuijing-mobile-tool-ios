//
//  MainView.swift
//  长须鲸手机工具 - 主界面（本机 / 设备 / 我的）+ 全局确认弹窗
//

import SwiftUI

struct MainView: View {
    @EnvironmentObject var app: AppState

    private var brand: Color { Color(red: 11/255, green: 182/255, blue: 198/255) }

    var body: some View {
        TabView {
            ContentView()
                .tabItem { Label("本机", systemImage: "iphone") }
            DevicesView()
                .tabItem { Label("设备", systemImage: "wifi") }
            MeView()
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
        .tint(brand)
        .onAppear {
            if app.loggedIn {
                app.connectGateway()
                app.refreshDevices()
                app.startDiscovery()
            }
        }
        .overlay(toastOverlay)
        .sheet(item: $app.pendingPair) { pair in pairSheet(pair) }
        .sheet(item: $app.pendingAsk) { ask in askSheet(ask) }
        .sheet(isPresented: Binding(get: { app.pendingShareURL != nil },
                                   set: { if !$0 { app.pendingShareURL = nil } })) {
            if let u = app.pendingShareURL { ShareSheet(items: [u]) }
        }
    }

    // MARK: 顶部小而白底 Toast
    private var toastOverlay: some View {
        VStack {
            if !app.toast.isEmpty {
                Text(app.toast)
                    .font(.footnote)
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.95))
                    .cornerRadius(10)
                    .shadow(radius: 4)
                    .padding(.top, 60)
                    .transition(.move(edge: .top))
            }
            Spacer()
        }
        .animation(.easeInOut, value: app.toast)
    }

    // MARK: 配对确认弹窗（小而白底）
    private func pairSheet(_ pair: PendingPair) -> some View {
        VStack(spacing: 18) {
            Text("配对请求").font(.title2.bold())
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(title: "设备", value: pair.peerName)
                InfoRow(title: "平台", value: platformName(pair.platform))
                InfoRow(title: "账号", value: pair.account.isEmpty ? "未登录" : pair.account)
            }
            HStack(spacing: 16) {
                Button("拒绝") { app.acceptPair(false) }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                Button("接受并信任") { app.acceptPair(true) }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(28)
        .background(Color.white)
    }

    // MARK: 动作确认弹窗（屏幕 / 文件 / 紧急申请）
    private func askSheet(_ ask: PendingAsk) -> some View {
        VStack(spacing: 18) {
            Text(askTitle(ask)).font(.title2.bold())
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(title: "来源", value: ask.fromName)
                InfoRow(title: "平台", value: platformName(ask.platform))
                if ask.kind == "file_ask" {
                    InfoRow(title: "文件", value: ask.fileName)
                    InfoRow(title: "大小", value: ByteCountFormatter.string(fromByteCount: ask.size, countStyle: .file))
                }
            }
            HStack(spacing: 16) {
                Button("拒绝") { app.denyAsk() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                Button("接受") { app.acceptAsk() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(28)
        .background(Color.white)
    }

    private func askTitle(_ ask: PendingAsk) -> String {
        switch ask.kind {
        case "screen_offer", "screen_ask": return "屏幕共享请求"
        case "file_ask": return "接收文件"
        case "pull_ask": return ask.pullKind == "file" ? "紧急申请文件" : "紧急申请屏幕"
        default: return "互联请求"
        }
    }

    private func platformName(_ p: String) -> String {
        switch p {
        case "win": return "Windows"
        case "android": return "安卓"
        case "ios": return "iOS"
        default: return p
        }
    }
}

// MARK: - 我的

struct MeView: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        NavigationView {
            List {
                Section("账号") {
                    InfoRow(title: "当前账号", value: app.loginName.isEmpty ? "未登录" : app.loginName)
                    InfoRow(title: "越狱状态",
                            value: app.jailbroken ? "已越狱（高级功能已解锁）" : "未越狱（仅单向投屏/查看）")
                    Toggle("离线模式", isOn: $app.offlineMode)
                }

                Section("屏幕发送（未越狱单向）") {
                    BroadcastPickerView()
                        .frame(height: 44)
                }

                if app.jailbroken {
                    Section("越狱高级功能") {
                        NavigationLink(destination: JBControlView()) {
                            Label("反向控制 / 后台常驻 / 远程装 IPA", systemImage: "lock.shield")
                        }
                    }
                }

                Section("关于") {
                    InfoRow(title: "版本",
                            value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.0")
                    InfoRow(title: "开发者", value: "长须鲸")
                }

                Section {
                    Button(role: .destructive) { app.logout() } label: {
                        Label("退出登录", systemImage: "arrow.right.square")
                    }
                }
            }
            .navigationTitle("我的")
        }
    }
}
