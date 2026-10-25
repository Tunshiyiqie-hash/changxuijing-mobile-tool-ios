//
//  SetCodeView.swift
//  长须鲸手机工具 - 首次登录后强制设置 6 位安全码
//

import SwiftUI

struct SetCodeView: View {
    @EnvironmentObject var app: AppState
    @State private var code = ""
    @State private var confirm = ""
    @State private var errorText = ""
    @State private var busy = false

    var body: some View {
        NavigationView {
            VStack(spacing: 18) {
                Text("设置 6 位安全码").font(.title2.bold())
                Text("用于跨账号互联与紧急申请，请牢记").foregroundColor(.secondary).font(.footnote)
                SecureField("6 位数字", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .frame(maxWidth: 200)
                SecureField("再次输入", text: $confirm)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .frame(maxWidth: 200)
                if !errorText.isEmpty { Text(errorText).foregroundColor(.red).font(.footnote) }
                Button(action: submit) {
                    HStack {
                        if busy { ProgressView().tint(.white) }
                        Text("完成")
                    }
                    .frame(maxWidth: .infinity).padding()
                    .background(Color(red: 11/255, green: 182/255, blue: 198/255))
                    .foregroundColor(.white).cornerRadius(10)
                }
            }
            .padding(28)
            .navigationTitle("安全码")
        }
    }

    private func submit() {
        errorText = ""
        guard code.count == 6, code.allSatisfy({ $0.isNumber }) else {
            errorText = "安全码必须是 6 位数字"; return
        }
        guard code == confirm else { errorText = "两次输入不一致"; return }
        busy = true
        APIClient.shared.setCode(code) { r in
            busy = false
            switch r {
            case .success:
                APIClient.shared.setCodeSet(true)
                app.needsSetCode = false
                app.registerDeviceIfNeeded()
            case .failure(let e):
                errorText = "设置失败：\(String(describing: e))"
            }
        }
    }
}
