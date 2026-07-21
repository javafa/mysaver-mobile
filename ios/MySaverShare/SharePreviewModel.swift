//
//  SharePreviewModel.swift
//  MySaverShare
//
//  ShareSheetView 의 ObservableObject. URL preview / 폴더 목록 / 노트 / 저장 상태.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class SharePreviewModel: ObservableObject {

    // MARK: - Inputs

    let sharedUrl: String
    let token: String?

    // MARK: - Preview state

    @Published var isPreviewLoading: Bool = true
    @Published var title: String? = nil
    @Published var domain: String
    @Published var ogImageUrl: String? = nil
    @Published var platform: String
    @Published var contentType: String = "link"

    // MARK: - Folder state

    @Published var folders: [FolderInfo] = []
    @Published var selectedFolder: FolderInfo? = nil

    // MARK: - Edit state

    @Published var note: String = ""
    @Published var tags: [String] = []  // Phase 1: empty → UI shows "uncategorized"

    // MARK: - Save state

    enum SaveStatus {
        case idle
        case saving
        case success(message: String)
        case failure(message: String)
    }
    @Published var saveStatus: SaveStatus = .idle

    // MARK: - Derived

    var displayTitle: String {
        if let t = title, !t.isEmpty { return t }
        return "(제목 없음)"
    }

    var displayDate: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ko_KR")
        fmt.dateFormat = "yyyy. M. d."
        return fmt.string(from: Date())
    }

    var isSaving: Bool {
        if case .saving = saveStatus { return true }
        return false
    }

    var isAuthenticated: Bool { token != nil }

    init(sharedUrl: String, token: String?) {
        self.sharedUrl = sharedUrl
        self.token = token
        self.domain = URL(string: sharedUrl)?.host ?? ""
        self.platform = SharePreviewModel.detectPlatform(from: sharedUrl)
    }

    // MARK: - Loaders

    func loadPreview() async {
        guard let token = token else {
            isPreviewLoading = false
            return
        }
        let preview = await ShareAPI.fetchPreview(url: sharedUrl, token: token)
        if let p = preview {
            NSLog("[MySaverShare] preview OK title=%@ og=%@", p.title ?? "(nil)", p.ogImageUrl ?? "(nil)")
            self.title = p.title
            self.domain = p.domain.isEmpty ? self.domain : p.domain
            self.ogImageUrl = p.ogImageUrl
            self.platform = p.platform
            self.contentType = p.contentType
        } else {
            NSLog("[MySaverShare] preview FAILED — backend not deployed or 401/timeout")
        }
        self.isPreviewLoading = false
    }

    func loadFolders() async {
        guard let token = token else { return }
        let fetched = await ShareAPI.fetchFolders(token: token)
        NSLog("[MySaverShare] folders 개수=%d", fetched.count)
        self.folders = fetched
    }

    // MARK: - Save

    /// "추가하기" 탭 시 호출. 성공 시 true.
    func save() async -> Bool {
        guard let token = token else {
            saveStatus = .failure(message: "로그인 후 이용해주세요")
            return false
        }
        saveStatus = .saving
        let itemId = UUID().uuidString
        let syncOk = await ShareAPI.postSync(
            itemId: itemId,
            url: sharedUrl,
            domain: domain,
            platform: platform,
            contentType: contentType,
            title: title,
            note: note.isEmpty ? nil : note,
            tags: tags,
            thumbnailUrl: ogImageUrl,
            token: token
        )
        if !syncOk {
            saveStatus = .failure(message: "저장 실패 — 앱을 열면 재시도됩니다")
            return false
        }
        if let folder = selectedFolder {
            let linkOk = await ShareAPI.postFolderLink(
                folderId: folder.id, itemId: itemId, token: token
            )
            if linkOk {
                saveStatus = .success(message: "‘\(folder.name)’에 저장됨")
            } else {
                saveStatus = .failure(message: "폴더 연결 실패 — 앱에서 확인해주세요")
                return false
            }
        } else {
            saveStatus = .success(message: "저장됨")
        }
        // 동기화 성공: pending 제거
        UserDefaults(suiteName: ShareConfig.appGroup)?.removeObject(
            forKey: ShareConfig.pendingShareKey
        )
        return true
    }

    static func detectPlatform(from urlString: String) -> String {
        let host = URL(string: urlString)?.host?.lowercased() ?? ""
        if host.contains("youtube.com") || host.contains("youtu.be") { return "youtube" }
        if host.contains("instagram.com") { return "instagram" }
        if host.contains("pinterest.") { return "pinterest" }
        return "unknown"
    }
}
