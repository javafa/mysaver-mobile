//
//  ShareAPI.swift
//  MySaverShare
//
//  Share Extension 이 호출하는 백엔드 API 클라이언트.
//  기존 ShareViewController 의 인라인 호출을 분리.
//

import Foundation

struct FolderInfo: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let emoji: String?
    let color: String?
}

struct PreviewInfo: Decodable {
    let url: String
    let domain: String
    let title: String?
    let ogImageUrl: String?
    let platform: String
    let contentType: String
}

enum ShareAPI {

    // MARK: - GET /api/items/preview

    static func fetchPreview(url: String, token: String) async -> PreviewInfo? {
        // YouTube 는 oEmbed 직접 호출 — 봇 차단 / 백엔드 지연 무관, 한 hop 단축.
        // 실패 시 백엔드 폴백.
        if isYouTubeURL(url), let oembed = await fetchYouTubeOEmbed(url: url) {
            return oembed
        }

        var components = URLComponents(string: "\(ShareConfig.apiBase)/api/items/preview")
        components?.queryItems = [URLQueryItem(name: "url", value: url)]
        guard let endpoint = components?.url else { return nil }

        var req = URLRequest(url: endpoint)
        // 백엔드는 HTML fetch (최대 6s) 만 동기로 처리 — S3 업로드는 백그라운드.
        // 약한 셀룰러 / 느린 기기에서도 cold path 통과하도록 여유 있게 12s.
        req.timeoutInterval = 12
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return nil }
            return try? JSONDecoder().decode(PreviewInfo.self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - YouTube oEmbed (백엔드 우회)

    private static func isYouTubeURL(_ url: String) -> Bool {
        let host = URL(string: url)?.host?.lowercased() ?? ""
        return host.contains("youtube.com") || host == "youtu.be"
    }

    private static func fetchYouTubeOEmbed(url: String) async -> PreviewInfo? {
        guard let encoded = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let endpoint = URL(string: "https://www.youtube.com/oembed?url=\(encoded)&format=json")
        else { return nil }

        var req = URLRequest(url: endpoint)
        req.timeoutInterval = 4

        struct OEmbed: Decodable {
            let title: String?
            let thumbnail_url: String?
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return nil }
            guard let o = try? JSONDecoder().decode(OEmbed.self, from: data) else { return nil }
            return PreviewInfo(
                url: url,
                domain: URL(string: url)?.host?.lowercased() ?? "",
                title: o.title,
                ogImageUrl: o.thumbnail_url,
                platform: "youtube",
                contentType: "video"
            )
        } catch {
            return nil
        }
    }

    // MARK: - GET /api/folders/

    static func fetchFolders(token: String) async -> [FolderInfo] {
        guard let url = URL(string: "\(ShareConfig.apiBase)/api/folders/") else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return [] }
            return (try? JSONDecoder().decode([FolderInfo].self, from: data)) ?? []
        } catch {
            return []
        }
    }

    // MARK: - POST /api/items/sync

    static func postSync(
        itemId: String,
        url: String,
        domain: String,
        platform: String,
        contentType: String,
        title: String?,
        note: String?,
        tags: [String],
        thumbnailUrl: String?,
        token: String
    ) async -> Bool {
        guard let endpoint = URL(string: "\(ShareConfig.apiBase)/api/items/sync") else { return false }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let now = ISO8601DateFormatter().string(from: Date())
        var item: [String: Any] = [
            "id": itemId,
            "url": url,
            "domain": domain,
            "platform": platform,
            "contentType": contentType,
            "createdAt": now,
            "updatedAt": now,
            "source": "share-extension",
            "metadataSource": title != nil || thumbnailUrl != nil ? "og" : "minimal",
            "tags": tags,
        ]
        if let title = title { item["title"] = title }
        if let note = note { item["note"] = note }
        if let thumb = thumbnailUrl { item["thumbnailUrl"] = thumb }

        let payload: [String: Any] = ["items": [item]]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse,
               (200..<300).contains(http.statusCode) {
                return true
            }
            return false
        } catch {
            return false
        }
    }

    // MARK: - POST /api/folders/{id}/items

    static func postFolderLink(folderId: Int, itemId: String, token: String) async -> Bool {
        guard let endpoint = URL(string: "\(ShareConfig.apiBase)/api/folders/\(folderId)/items") else {
            return false
        }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 8
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let payload: [String: Any] = ["itemId": itemId]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse,
               (200..<300).contains(http.statusCode) {
                return true
            }
            return false
        } catch {
            return false
        }
    }
}
