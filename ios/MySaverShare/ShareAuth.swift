//
//  ShareAuth.swift
//  MySaverShare
//
//  공유 시트를 그리기 전에 토큰의 "존재" 가 아니라 "유효성" 을 판정한다.
//  App Group 에 남아있는 만료/폐기 토큰으로 시트를 띄우면 preview·folders 가
//  전부 401 로 떨어져 빈 썸네일 + "(제목 없음)" 만 남기 때문.
//
//  판정 순서:
//  1) 로컬 JWT `exp` 디코드 — 네트워크 없이 만료를 즉시 걸러낸다
//  2) GET /api/auth/me — 폐기·삭제·정지 계정은 서버만 알 수 있다
//

import Foundation

/// 토큰 판정 결과.
enum ShareAuthState {
    /// 유효 — 공유 시트 진행.
    case valid
    /// 토큰 없음 — 로그인한 적 없음.
    case signedOut
    /// 만료/폐기 — 재로그인 필요. 저장된 토큰은 폐기한다.
    case expired
    /// 계정 정지 (403).
    case banned
    /// 서버 도달 실패 — 판단 보류. 토큰을 무효로 단정하지 않는다.
    case unreachable
}

enum ShareAuth {

    /// 토큰의 유효성을 판정한다. 저장된 토큰이 만료/폐기로 확인되면 App Group 에서 제거.
    static func verify(token: String?) async -> ShareAuthState {
        guard let token, !token.isEmpty else {
            NSLog("[MySaverShare] auth: 토큰 없음")
            return .signedOut
        }

        // 1) 로컬 만료 검사 — 네트워크 왕복 없이 가장 흔한 케이스를 먼저 처리.
        if isExpired(token) {
            NSLog("[MySaverShare] auth: 로컬 exp 만료")
            discardToken()
            return .expired
        }

        // 2) 서버 검증.
        let state = await fetchMe(token: token)
        NSLog("[MySaverShare] auth: 서버 판정 = %@", String(describing: state))
        if state == .expired {
            discardToken()
        }
        return state
    }

    // MARK: - 서버 검증

    private static func fetchMe(token: String) async -> ShareAuthState {
        guard let endpoint = URL(string: "\(ShareConfig.apiBase)/api/auth/me") else {
            return .unreachable
        }
        var req = URLRequest(url: endpoint)
        // 공유 시트 진입 지연에 직결되는 경로 — 짧게 끊고, 실패 시엔 보류 처리.
        req.timeoutInterval = 6
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return .unreachable }
            switch http.statusCode {
            case 200..<300: return .valid
            case 401: return .expired
            case 403: return .banned
            default:
                // 5xx 등 서버측 장애 — 토큰 문제로 단정하지 않는다.
                return .unreachable
            }
        } catch {
            return .unreachable
        }
    }

    // MARK: - 로컬 JWT exp

    /// JWT payload 의 `exp` 를 디코드해 만료 여부를 본다.
    /// 서명은 검증하지 않는다 — 서버 검증의 사전 필터일 뿐.
    /// 파싱 실패 시 `false` (만료로 단정하지 않고 서버 판정에 맡긴다).
    static func isExpired(_ token: String, now: Date = Date()) -> Bool {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let data = base64URLDecode(String(parts[1])),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? Double
        else { return false }

        // 시계 오차 / 요청 왕복 시간 대비 30s 여유.
        return Date(timeIntervalSince1970: exp) <= now.addingTimeInterval(30)
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var s = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = s.count % 4
        if remainder > 0 {
            s += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: s)
    }

    // MARK: - 토큰 폐기

    /// 무효로 확인된 토큰을 App Group 에서 제거 — 메인 앱도 같은 키를 본다.
    private static func discardToken() {
        UserDefaults(suiteName: ShareConfig.appGroup)?
            .removeObject(forKey: ShareConfig.tokenKey)
    }
}
