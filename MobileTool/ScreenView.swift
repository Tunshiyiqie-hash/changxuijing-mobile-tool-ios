//
//  ScreenView.swift
//  长须鲸手机工具 - 远程屏幕查看（未越狱仅看；越狱显示控制层并回传 ctrl）
//

import SwiftUI

struct ScreenView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                ZStack {
                    if let img = app.viewingImage {
                        if app.jailbroken {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .gesture(dragGesture(geo.size))
                        } else {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(width: geo.size.width, height: geo.size.height)
                        }
                    } else {
                        ProgressView("等待画面…").tint(.white)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }

            VStack {
                HStack {
                    Button {
                        app.stopViewing()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .padding(8)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    Spacer()
                    Text(app.jailbroken ? "可控制" : "仅观看")
                        .font(.caption)
                        .padding(6)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(6)
                }
                .foregroundColor(.white)
                .padding()

                Spacer()

                if app.jailbroken {
                    HStack(spacing: 18) {
                        keyButton("home", "house")
                        keyButton("back", "arrow.uturn.backward")
                        keyButton("recents", "square.stack")
                        keyButton("power", "power")
                        keyButton("volup", "speaker.wave.3")
                        keyButton("voldown", "speaker.wave.1")
                    }
                    .padding(.bottom, 24)
                }
            }
        }
    }

    // MARK: 触控手势（归一化坐标 0~1，协议 §3.4）
    private func dragGesture(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let x = min(max(v.location.x / size.width, 0), 1)
                let y = min(max(v.location.y / size.height, 0), 1)
                let ev = v.translation == .zero ? "down" : "move"
                app.sendControl(["t": "ctrl", "sid": app.currentViewSid,
                                 "action": "pointer", "ev": ev, "id": 0, "x": x, "y": y])
            }
            .onEnded { v in
                let x = min(max(v.location.x / size.width, 0), 1)
                let y = min(max(v.location.y / size.height, 0), 1)
                app.sendControl(["t": "ctrl", "sid": app.currentViewSid,
                                 "action": "pointer", "ev": "up", "id": 0, "x": x, "y": y])
            }
    }

    private func keyButton(_ code: String, _ icon: String) -> some View {
        Button {
            app.sendControl(["t": "ctrl", "sid": app.currentViewSid,
                             "action": "key", "ev": "down", "code": code])
        } label: {
            Image(systemName: icon)
                .padding(10)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
                .foregroundColor(.white)
        }
    }
}
