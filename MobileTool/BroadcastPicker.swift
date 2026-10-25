//
//  BroadcastPicker.swift
//  长须鲸手机工具 - 用 RPSystemBroadcastPickerView 拉起系统广播（未越狱单向推屏）
//

import SwiftUI
import ReplayKit

struct BroadcastPickerView: UIViewRepresentable {
    var extensionBundleID = "com.changxujing.mobiletool.broadcast"

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 220, height: 44))
        picker.preferredExtension = extensionBundleID
        picker.showsMicrophoneButton = false
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
