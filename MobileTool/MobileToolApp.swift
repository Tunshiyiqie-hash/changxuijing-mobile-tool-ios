//
//  MobileToolApp.swift
//  长须鲸手机工具
//

import SwiftUI

@main
struct MobileToolApp: App {
    @StateObject private var app = AppState.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .tint(Color(red: 11/255.0, green: 182/255.0, blue: 198/255.0))
        }
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        if !app.loggedIn && !app.offlineMode {
            LoginView()
        } else if app.loggedIn && app.needsSetCode && !app.offlineMode {
            SetCodeView()
        } else {
            MainView()
        }
    }
}
