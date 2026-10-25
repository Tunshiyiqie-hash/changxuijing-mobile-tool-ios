//
//  DevicesView.swift
//  长须鲸手机工具 - 同账号远程设备 + 局域网双向发现/配对 + 跨账号连接
//

import SwiftUI

struct DevicesView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var discovery = Discovery.shared

    @State private var showingScreen = false
    @State private var showingFilePicker = false
    @State private var fileTarget: RemoteDevice?
    @State private var showingCrossAccount = false
    @State private var crossAccount = ""
    @State private var crossCode = ""
    @State private var crossTicket = ""

    var body: some View {
        NavigationView {
            List {
                // MARK: 同账号设备
                Section("同账号设备") {
                    if app.remoteDevices.isEmpty {
                        Text("暂无设备，下拉刷新").foregroundColor(.secondary).font(.footnote)
                    }
                    ForEach(app.remoteDevices.filter { $0.deviceId != APIClient.shared.deviceId }) { d in
                        remoteRow(d)
                    }
                }

                // MARK: 附近电脑 / 附近设备（局域网双向发现）
                Section("附近电脑 / 设备") {
                    if discovery.peers.filter({ !$0.isSelf }).isEmpty {
                        Text("正在扫描局域网…").foregroundColor(.secondary).font(.footnote)
                    }
                    ForEach(discovery.peers.filter { !$0.isSelf }) { p in
                        peerRow(p)
                    }
                }

                Section {
                    Button("跨账号连接（对方账号 + 安全码）") {
                        showingCrossAccount = true
                    }
                } footer: {
                    Text("同账号设备可直接选择；跨账号需先通过对方账号名与安全码换取一次性票据。")
                        .font(.caption)
                }
            }
            .navigationTitle("设备")
            .onAppear {
                app.refreshDevices()
                discovery.start()
            }
            .refreshable { app.refreshDevices() }
            .sheet(isPresented: $showingScreen) { ScreenView() }
            .sheet(isPresented: $showingFilePicker) {
                FilePicker { url in
                    if let target = fileTarget {
                        app.offerRemoteFile(url: url, to: target)
                    } else {
                        app.offerLanFile(url: url)
                    }
                }
            }
            .sheet(isPresented: $showingCrossAccount) { crossAccountSheet }
        }
    }

    // MARK: 远程设备行
    private func remoteRow(_ d: RemoteDevice) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon(for: d.platform))
                    .foregroundColor(d.online ? Color(red: 11/255, green: 182/255, blue: 198/255) : .gray)
                VStack(alignment: .leading) {
                    Text(d.name)
                    Text("\(platformName(d.platform)) · \(d.online ? "在线" : "离线")")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                Button { app.pullScreen(to: d); showingScreen = true } label: {
                    Label("看屏幕", systemImage: "eye")
                }.disabled(!d.online)
                Button { app.pullFile(to: d) } label: {
                    Label("要文件", systemImage: "folder.badge.plus")
                }.disabled(!d.online)
                Button {
                    fileTarget = d
                    showingFilePicker = true
                } label: {
                    Label("发文件", systemImage: "square.and.arrow.up")
                }.disabled(!d.online)
            }
            .font(.footnote)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: 局域网设备行
    private func peerRow(_ p: Peer) -> some View {
        let status = discovery.pairStatus[p.id] ?? "idle"
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon(for: p.platform))
                    .foregroundColor(Color(red: 11/255, green: 182/255, blue: 198/255))
                VStack(alignment: .leading) {
                    Text(p.displayName)
                    Text("\(platformName(p.platform)) · \(p.account.isEmpty ? "未登录" : p.account)")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Text(statusText(status))
                    .font(.caption)
                    .foregroundColor(statusColor(status))
            }
            HStack(spacing: 10) {
                Button {
                    discovery.pair(p)
                } label: {
                    Label(status == "connected" ? "已连接" : "配对并连接", systemImage: "link")
                }
                .disabled(status == "waiting" || status == "connected")
                Button {
                    discovery.untrust(p.id)
                    app.toast = "已解除对 \(p.displayName) 的信任"
                } label: {
                    Label("解除信任", systemImage: "hand.thumbsdown")
                }
            }
            .font(.footnote)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func statusText(_ s: String) -> String {
        switch s {
        case "waiting": return "等待…"
        case "connected": return "已连接"
        case "rejected": return "已拒绝"
        default: return "未连接"
        }
    }

    private func statusColor(_ s: String) -> Color {
        switch s {
        case "connected": return .green
        case "rejected": return .red
        case "waiting": return .orange
        default: return .secondary
        }
    }

    // MARK: 跨账号票据
    private var crossAccountSheet: some View {
        NavigationView {
            VStack(spacing: 16) {
                TextField("对方账号名", text: $crossAccount)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                SecureField("对方安全码", text: $crossCode)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                if !crossTicket.isEmpty {
                    Text("票据已获取（5 分钟有效），可在设备列表选择对端。")
                        .font(.footnote).foregroundColor(.green)
                }
                Button("校验并换取票据") {
                    APIClient.shared.resolvePeer(account: crossAccount, code: crossCode) { r in
                        switch r {
                        case .success(let ticket):
                            crossTicket = ticket
                            app.toast = "跨账号票据已获取"
                        case .failure(let e):
                            app.toast = "校验失败：\(e)"
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(crossAccount.isEmpty || crossCode.count != 6)
                Spacer()
            }
            .padding(24)
            .navigationTitle("跨账号连接")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func icon(for p: String) -> String {
        switch p {
        case "win": return "desktopcomputer"
        case "android": return "smartphone"
        case "ios": return "iphone"
        default: return "questionmark"
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
