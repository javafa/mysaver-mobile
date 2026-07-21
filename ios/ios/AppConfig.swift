//
//  AppConfig.swift
//  ios
//
//  앱 전역 설정 상수. 환경별 분기는 #if DEBUG 로 처리.
//

import Foundation

enum AppConfig {
    #if DEBUG
    static let siteURL = URL(string: "https://mysaver.kr")!
    static let allowedHost = "mysaver.kr"
    // 로컬 개발 서버를 쓰려면 위 두 줄을 주석 처리하고 아래로 교체:
    //   static let siteURL = URL(string: "http://localhost:3000")!
    //   static let allowedHost = "localhost"
    // 그리고 Info.plist 에 NSAppTransportSecurity > NSAllowsLocalNetworking = YES 추가.
    #else
    static let siteURL = URL(string: "https://mysaver.kr")!
    static let allowedHost = "mysaver.kr"
    #endif

    /// 메인 앱 ↔ Share Extension 간 데이터 공유용 App Group ID.
    /// Xcode > Signing & Capabilities 에서 두 target 모두에 추가해야 함.
    static let appGroup = "group.kr.mysaver.shared"

    /// Share Extension 이 저장하고 메인 앱이 소비하는 키.
    static let pendingShareKey = "pending_share_url"

    /// 인증 토큰 키 (App Group UserDefaults 에 저장).
    static let tokenKey = "auth_token"

    /// Share Extension → 메인 앱 호출에 쓰는 custom URL scheme.
    /// Info.plist > CFBundleURLTypes 에 등록 필요.
    static let urlScheme = "mysaver"
}
