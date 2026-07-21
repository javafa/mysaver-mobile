//
//  ContentView.swift
//  ios
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var sharedStore: SharedStore

    var body: some View {
        WebViewContainer(initialURL: AppConfig.siteURL, sharedStore: sharedStore)
            .ignoresSafeArea(.container, edges: .bottom)
    }
}

#Preview {
    ContentView()
        .environmentObject(SharedStore())
}
