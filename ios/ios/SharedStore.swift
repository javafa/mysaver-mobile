//
//  SharedStore.swift
//  ios
//
//  App Group UserDefaults 기반 공유 저장소.
//  - JWT 토큰 보관 (메인앱 WebView 에서 받아 저장 → Share Extension 에서 사용)
//  - Share Extension 이 남긴 공유 URL 을 메인앱이 소비
//

import Foundation
import Combine

final class SharedStore: ObservableObject {
    private var pendingURLHandler: ((String) -> Void)?
    private var pendingOAuthHandler: ((URL) -> Void)?

    private var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: AppConfig.appGroup) ?? .standard
    }

    // MARK: - 토큰

    func saveToken(_ token: String) {
        sharedDefaults.set(token, forKey: AppConfig.tokenKey)
    }

    func clearToken() {
        sharedDefaults.removeObject(forKey: AppConfig.tokenKey)
    }

    func currentToken() -> String? {
        sharedDefaults.string(forKey: AppConfig.tokenKey)
    }

    // MARK: - 공유 URL 큐

    func setPendingURLHandler(_ handler: @escaping (String) -> Void) {
        pendingURLHandler = handler
    }

    /// Share Extension 이 남긴 URL 을 하나 꺼낸다 (있으면 제거).
    func consumePendingSharedURL() -> String? {
        guard let url = sharedDefaults.string(forKey: AppConfig.pendingShareKey) else { return nil }
        sharedDefaults.removeObject(forKey: AppConfig.pendingShareKey)
        return url
    }

    // MARK: - OAuth 콜백

    /// OAuthCoordinator 가 SFSafariViewController 를 띄울 때 등록.
    /// `mysaver://oauth?token=...` 가 도착하면 호출된다.
    func setOAuthCallbackHandler(_ handler: @escaping (URL) -> Void) {
        pendingOAuthHandler = handler
    }

    func clearOAuthCallbackHandler() {
        pendingOAuthHandler = nil
    }

    /// `mysaver://share?url=<encoded>` 또는 `mysaver://oauth?token=...` 처리.
    func handleIncomingURL(_ url: URL) {
        guard url.scheme == AppConfig.urlScheme else { return }

        switch url.host {
        case "share":
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let sharedURL = components.queryItems?.first(where: { $0.name == "url" })?.value else {
                return
            }
            pendingURLHandler?(sharedURL)
        case "oauth":
            pendingOAuthHandler?(url)
        default:
            return
        }
    }
}
