//
//  ShareViewController.swift
//  MySaverShare
//
//  iOS Share Extension 진입점. URL 추출 후 SwiftUI ShareSheetView 를 루트로 임베드.
//
//  흐름:
//  1) inputItems 에서 URL 추출 + App Group 에 URL stash (메인앱이 소비)
//  2) 토큰 유효성 판정 (ShareAuth) — 존재 여부가 아니라 만료/폐기까지
//  3) 유효하면 ShareSheetView, 아니면 ShareLoginPromptView 를 root child 로 임베드
//  4) onClose 콜백 → extensionContext.completeRequest
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {

    private var hostingController: UIHostingController<AnyView>?
    /// SwiftUI 의 `@ObservedObject` 는 모델 retain 책임이 없으므로 컨트롤러가 강참조 유지.
    private var previewModel: SharePreviewModel?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemBackground
        Task { await begin() }
    }

    // MARK: - Flow

    private func begin() async {
        guard let url = await extractURL() else {
            await MainActor.run {
                embed(AnyView(ShareFallbackView(message: "공유된 URL 을 찾을 수 없습니다")))
            }
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            complete()
            return
        }
        let urlString = url.absoluteString
        NSLog("[MySaverShare] URL 추출: %@", urlString)

        // App Group: pending stash + 토큰 확인
        let defaults = UserDefaults(suiteName: ShareConfig.appGroup)
        if defaults == nil {
            NSLog("[MySaverShare] App Group UserDefaults nil — entitlements/provisioning 확인 필요")
        }
        defaults?.set(urlString, forKey: ShareConfig.pendingShareKey)
        let token = defaults?.string(forKey: ShareConfig.tokenKey)

        // 토큰 판정이 끝나기 전에는 시트를 그리지 않는다. 무효 토큰으로 시트를 띄우면
        // preview/folders 가 전부 401 이라 빈 썸네일 + "(제목 없음)" 만 남는다.
        await MainActor.run { embed(AnyView(ShareLoadingView())) }
        let auth = await ShareAuth.verify(token: token)

        await MainActor.run {
            switch auth {
            case .signedOut:
                showLoginPrompt(reason: .signedOut, urlString: urlString)
            case .expired:
                showLoginPrompt(reason: .expired, urlString: urlString)
            case .banned:
                showLoginPrompt(reason: .banned, urlString: urlString)

            case .valid, .unreachable:
                // unreachable: 서버 도달 실패는 토큰 무효의 근거가 아니다.
                // 로그인한 사용자를 오프라인이라는 이유로 로그아웃 취급하지 않고,
                // 시트를 띄운 뒤 저장 실패 경로가 재시도를 안내하게 둔다.
                guard let token else {
                    showLoginPrompt(reason: .signedOut, urlString: urlString)
                    return
                }
                let model = SharePreviewModel(sharedUrl: urlString, token: token)
                self.previewModel = model
                let sheet = ShareSheetView(
                    model: model,
                    onClose: { [weak self] in self?.complete() }
                )
                embed(AnyView(sheet))
            }
        }
    }

    @MainActor
    private func showLoginPrompt(reason: ShareLoginPromptView.Reason, urlString: String) {
        let prompt = ShareLoginPromptView(
            reason: reason,
            sharedUrl: urlString,
            onOpenMainApp: { [weak self] in self?.openMainApp(with: urlString) },
            onClose: { [weak self] in self?.complete() }
        )
        embed(AnyView(prompt))
    }

    /// 토큰 없을 때 "MySaver 열기" 탭 시 호출. 메인 앱이 pending_share_url 을 소비.
    @MainActor
    private func openMainApp(with url: String) {
        let encoded = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
        guard let deepLink = URL(string: "\(ShareConfig.urlScheme)://share?url=\(encoded)") else {
            complete()
            return
        }
        // Share Extension 에서 openURL 호출은 responder chain 으로 위임
        var responder: UIResponder? = self
        while let r = responder {
            if let app = r as? UIApplication {
                app.open(deepLink, options: [:], completionHandler: nil)
                break
            }
            #if compiler(>=5.9)
            if r.responds(to: NSSelectorFromString("openURL:")) {
                _ = r.perform(NSSelectorFromString("openURL:"), with: deepLink)
                break
            }
            #endif
            responder = r.next
        }
        complete()
    }

    @MainActor
    private func embed(_ root: AnyView) {
        // 기존 child 제거
        if let prev = hostingController {
            prev.willMove(toParent: nil)
            prev.view.removeFromSuperview()
            prev.removeFromParent()
        }
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
        hostingController = host
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    // MARK: - URL 추출

    private func extractURL() async -> URL? {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return nil }
        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let value = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) {
                        if let u = value as? URL { return u }
                        if let s = value as? String, let u = URL(string: s) { return u }
                    }
                }
            }
        }
        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let value = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier),
                       let text = value as? String,
                       let u = firstURL(in: text) {
                        return u
                    }
                }
            }
        }
        return nil
    }

    private func firstURL(in text: String) -> URL? {
        let types = NSTextCheckingResult.CheckingType.link.rawValue
        guard let det = try? NSDataDetector(types: types) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return det.firstMatch(in: text, options: [], range: range)?.url
    }
}

// MARK: - Loading / Fallback views

/// 토큰 판정 중 표시. 시트와 로그인 안내 중 무엇을 그릴지 아직 모르는 구간.
struct ShareLoadingView: View {
    var body: some View {
        VStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

struct ShareFallbackView: View {
    let message: String
    var body: some View {
        VStack {
            Spacer()
            Text(message)
                .font(.system(size: 14, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

/// Share Extension 전용 상수. 메인 앱의 `AppConfig` 와 값 일치.
enum ShareConfig {
    static let appGroup = "group.kr.mysaver.shared"
    static let pendingShareKey = "pending_share_url"
    static let tokenKey = "auth_token"
    static let urlScheme = "mysaver"
    /// prod API 호스트. 사이트(`mysaver.kr`) 와 다른 서브도메인.
    static let apiBase = "https://api.mysaver.kr"
}
