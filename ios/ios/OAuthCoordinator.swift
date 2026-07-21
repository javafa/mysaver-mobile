//
//  OAuthCoordinator.swift
//  ios
//
//  SFSafariViewController 기반 OAuth 흐름.
//
//  배경:
//  - Google 은 WKWebView 안에서 accounts.google.com 접속을 거부함 (Error 403: disallowed_useragent).
//  - 또 ASWebAuthenticationSession 은 다른 앱으로의 URL scheme 점프(예: KakaoTalk 앱 호출) 를 보안상
//    차단함 → "브라우저 설정을 확인하세요" 다이얼로그가 뜨면서 카톡 앱 로그인 불가.
//  → 시스템 Safari 와 동일한 UA / 쿠키 jar 를 쓰면서 외부 앱 호출도 허용하는
//    SFSafariViewController 를 모달로 띄워서 OAuth 를 진행한다.
//
//  흐름:
//  1) WebView 가 'openOAuth' 메시지 전달 → start(provider:) 호출
//  2) SFSafariViewController 로 https://mysaver.kr/login?platform=ios&autoOauth=<provider> 열기
//  3) 사용자가 카카오/구글/네이버 로그인 (필요시 카톡 앱으로 점프 후 복귀)
//  4) 프론트가 OAuth 완료 후 mysaver://oauth?token=...&user=base64&isNewUser=...&hasHandle=... 로 redirect
//  5) iOS 가 mysaver:// 를 받아 onOpenURL → SharedStore.handleIncomingURL 로 전달
//     → 우리가 등록해둔 OAuth 콜백 핸들러가 호출됨
//  6) Safari 모달 dismiss → App Group 에 토큰 저장 → 메인 WebView 에 주입 + 라우팅
//

import Foundation
import SafariServices
import UIKit
import WebKit

final class OAuthCoordinator: NSObject, SFSafariViewControllerDelegate {
    weak var webView: WKWebView?
    let sharedStore: SharedStore
    private var safariVC: SFSafariViewController?

    init(webView: WKWebView?, sharedStore: SharedStore) {
        self.webView = webView
        self.sharedStore = sharedStore
    }

    func start(provider: String) {
        guard let startURL = makeStartURL(provider: provider) else { return }

        // 이전 세션이 살아있으면 정리.
        dismissSafari()

        // mysaver://oauth?... 가 iosApp.onOpenURL → SharedStore.handleIncomingURL 로
        // 들어왔을 때 호출될 콜백 등록.
        sharedStore.setOAuthCallbackHandler { [weak self] url in
            self?.handleCallback(url: url)
        }

        let safari = SFSafariViewController(url: startURL)
        safari.delegate = self
        safari.modalPresentationStyle = .formSheet
        // 기본은 진한 보라색 — 앱 컬러로 바꾸고 싶으면 여기서.
        // safari.preferredBarTintColor = ...
        self.safariVC = safari

        guard let presenter = topViewController() else { return }
        presenter.present(safari, animated: true)
    }

    // MARK: -

    private func makeStartURL(provider: String) -> URL? {
        var components = URLComponents(url: AppConfig.siteURL.appendingPathComponent("login"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "platform", value: "ios"),
            URLQueryItem(name: "autoOauth", value: provider),
        ]
        return components?.url
    }

    private func handleCallback(url: URL) {
        guard url.scheme == AppConfig.urlScheme,
              url.host == "oauth",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return
        }

        var params: [String: String] = [:]
        for item in components.queryItems ?? [] {
            if let value = item.value { params[item.name] = value }
        }

        guard let token = params["token"] else { return }
        let isNewUser = params["isNewUser"] == "1"
        let hasHandle = params["hasHandle"] == "1"
        let userBase64 = params["user"] ?? ""

        // App Group 에 토큰 저장 — Share Extension 에서 재사용.
        sharedStore.saveToken(token)

        let path: String
        if isNewUser && !hasHandle {
            path = "/setup-handle"
        } else if isNewUser {
            path = "/welcome"
        } else {
            path = "/"
        }

        // 콜백을 받았으니 핸들러는 비우고 Safari 모달 닫기.
        sharedStore.clearOAuthCallbackHandler()
        dismissSafari()
        injectAuth(token: token, userBase64: userBase64, path: path)
    }

    private func dismissSafari() {
        guard let safari = safariVC else { return }
        self.safariVC = nil
        DispatchQueue.main.async {
            safari.dismiss(animated: true)
        }
    }

    private func injectAuth(token: String, userBase64: String, path: String) {
        let tokenLit = token.escapedForJSString()
        let pathLit = path.escapedForJSString()
        // 프론트는 btoa(unescape(encodeURIComponent(json))) 로 인코딩 → 역순으로 UTF-8 안전 디코드.
        let userLit = userBase64.isEmpty
            ? "null"
            : "JSON.parse(decodeURIComponent(escape(atob('\(userBase64.escapedForJSString())'))))"

        let js = """
        (function() {
          try {
            localStorage.setItem('saveme_token', '\(tokenLit)');
            var u = \(userLit);
            if (u) localStorage.setItem('saveme_user', JSON.stringify(u));
            window.location.href = '\(pathLit)';
          } catch (e) {}
        })();
        """
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    private func topViewController() -> UIViewController? {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })

        guard var top = keyWindow?.rootViewController else { return nil }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    // MARK: - SFSafariViewControllerDelegate

    /// 사용자가 "Done" 버튼이나 swipe-down 으로 닫은 경우.
    /// (handleCallback 에서 프로그래매틱하게 dismiss 한 경우엔 호출되지 않음.)
    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        sharedStore.clearOAuthCallbackHandler()
        self.safariVC = nil
    }
}

private extension String {
    func escapedForJSString() -> String {
        var s = self
        s = s.replacingOccurrences(of: "\\", with: "\\\\")
        s = s.replacingOccurrences(of: "'", with: "\\'")
        s = s.replacingOccurrences(of: "\n", with: "\\n")
        s = s.replacingOccurrences(of: "\r", with: "\\r")
        return s
    }
}
