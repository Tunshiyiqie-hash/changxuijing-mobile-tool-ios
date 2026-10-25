//
//  LoginView.swift
//  长须鲸手机工具 - 登录/注册 + 离线模式开关
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var app: AppState
    @State private var login = ""
    @State private var password = ""
    @State private var isRegister = false
    @State private var busy = false
    @State private var errorText = ""

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 245/255, green: 250/255, blue: 251/255).ignoresSafeArea()
                VStack(spacing: 18) {
                    Text("长须鲸手机工具")
                        .font(.largeTitle.bold())
                        .foregroundColor(Color(red: 11/255, green: 182/255, blue: 198/255))
                    Text(isRegister ? "注册新账号" : "登录已有账号")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextField("账号", text: $login)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                    SecureField("密码", text: $password)
                        .textFieldStyle(.roundedBorder)

                    if !errorText.isEmpty {
                        Text(errorText).font(.footnote).foregroundColor(.red)
                    }

                    Button(action: submit) {
                        HStack {
                            if busy { ProgressView().tint(.white) }
                            Text(isRegister ? "注册并登录" : "登录")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(red: 11/255, green: 182/255, blue: 198/255))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(busy)

                    Button(isRegister ? "已有账号？去登录" : "没有账号？去注册") {
                        isRegister.toggle()
                        errorText = ""
                    }
                    .font(.footnote)

                    Toggle(isOn: $app.offlineMode) {
                        Text("离线模式（仅本机功能）").font(.footnote)
                    }
                    .padding(.top, 8)
                }
                .padding(28)
            }
            .navigationTitle("")
            .navigationBarHidden(true)
        }
    }

    private func submit() {
        errorText = ""
        guard !login.isEmpty, !password.isEmpty else {
            errorText = "请输入账号和密码"; return
        }
        busy = true
        let api = APIClient.shared
        if isRegister {
            api.register(login: login, password: password) { r in
                busy = false
                switch r {
                case .success(let token):
                    app.onLoggedIn(token: token, login: login, codeSet: false)
                case .failure(let e):
                    errorText = "注册失败：\(String(describing: e))"
                }
            }
        } else {
            api.login(login: login, password: password) { r in
                busy = false
                switch r {
                case .success(let res):
                    app.onLoggedIn(token: res.token, login: login, codeSet: res.codeSet)
                case .failure(let e):
                    errorText = "登录失败：\(String(describing: e))"
                }
            }
        }
    }
}
