//
//  WebViewContainer.swift
//  ios
//
//  WKWebView 를 SwiftUI 로 감싸는 컨테이너.
//  - Web → Native: window.webkit.messageHandlers.mysaver.postMessage({...})
//  - Native → Web: window.dispatchEvent(new CustomEvent('mysaver:shared', { detail: { url } }))
//

import SwiftUI
import WebKit

struct WebViewContainer: UIViewRepresentable {
    let initialURL: URL
    let sharedStore: SharedStore

    func makeCoordinator() -> Coordinator {
        Coordinator(sharedStore: sharedStore)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: "mysaver")
        config.userContentController = userContent

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: initialURL))

        context.coordinator.webView = webView
        sharedStore.setPendingURLHandler { [weak coordinator = context.coordinator] url in
            coordinator?.dispatchSharedURL(url)
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        let sharedStore: SharedStore
        private var oauthCoordinator: OAuthCoordinator?

        init(sharedStore: SharedStore) {
            self.sharedStore = sharedStore
        }

        // MARK: Web → Native

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }

            switch type {
            case "setToken":
                if let token = body["token"] as? String {
                    sharedStore.saveToken(token)
                }
            case "clearToken":
                sharedStore.clearToken()
            case "openOAuth":
                if let provider = body["provider"] as? String {
                    let coordinator = oauthCoordinator ?? OAuthCoordinator(webView: webView, sharedStore: sharedStore)
                    oauthCoordinator = coordinator
                    coordinator.start(provider: provider)
                }
            default:
                break
            }
        }

        // MARK: Navigation

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let scheme = url.scheme?.lowercased() ?? ""

            // 1. 내부 도메인 (http/https on mysaver.kr or localhost) — WebView 에서 직접 로드.
            if scheme == "https" || scheme == "http" {
                if url.host == AppConfig.allowedHost || url.host == "localhost" {
                    decisionHandler(.allow)
                    return
                }
                // 외부 도메인은 사용자 직접 클릭(linkActivated) 시 Safari 로 위임.
                if navigationAction.navigationType == .linkActivated {
                    UIApplication.shared.open(url)
                    decisionHandler(.cancel)
                    return
                }
                decisionHandler(.allow)
                return
            }

            // 2. 커스텀 URL 스킴 (kakaokompassauth://, kakaolink://, kakaotalk://, mysaver://, market://, tel://, mailto:// 등)
            //    WKWebView 는 이런 스킴을 처리할 수 없으므로 시스템에 위임.
            //    카카오 OAuth 가 KakaoTalk 앱을 호출할 때 이 경로로 진입함.
            //    canOpenURL 이 true 를 반환하려면 Info.plist 의 LSApplicationQueriesSchemes 에 스킴이 등록되어 있어야 함.
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // 페이지 로드 직후, 대기 중인 공유 URL 이 있으면 전달.
            if let url = sharedStore.consumePendingSharedURL() {
                dispatchSharedURL(url)
            }
        }

        // MARK: Native → Web

        func dispatchSharedURL(_ url: String) {
            guard let webView = webView else { return }
            let safe = url.replacingOccurrences(of: "\\", with: "\\\\")
                          .replacingOccurrences(of: "'", with: "\\'")
            let js = "window.dispatchEvent(new CustomEvent('mysaver:shared', { detail: { url: '\(safe)' } }));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
