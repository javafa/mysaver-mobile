//
//  iosApp.swift
//  ios
//
//  MySaver iOS — WebView 기반 메인 앱.
//

import SwiftUI

@main
struct iosApp: App {
    @StateObject private var sharedStore = SharedStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sharedStore)
                .onOpenURL { url in
                    sharedStore.handleIncomingURL(url)
                }
        }
    }
}
