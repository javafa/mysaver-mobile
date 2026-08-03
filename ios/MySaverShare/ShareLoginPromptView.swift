//
//  ShareLoginPromptView.swift
//  MySaverShare
//
//  App Group 에 JWT 가 없을 때 공유 시트 대신 표시되는 로그인 안내 화면.
//  미리보기/폴더 API 는 토큰이 있어야 동작하므로, 비로그인 상태에서
//  빈 썸네일·"(제목 없음)" 이 노출되지 않도록 이 화면이 먼저 나온다.
//

import SwiftUI

struct ShareLoginPromptView: View {

    /// 안내 문구를 가르는 사유. `ShareAuth` 판정 결과에서 유래.
    enum Reason {
        case signedOut
        case expired
        case banned
    }

    let reason: Reason

    /// 저장 대기 중인 공유 URL — 도메인만 요약 표시.
    let sharedUrl: String

    /// "MySaver 앱에서 로그인" 탭 시 호출.
    var onOpenMainApp: () -> Void

    /// "나중에" / 닫기 탭 시 호출.
    var onClose: () -> Void

    private var domain: String {
        URL(string: sharedUrl)?.host ?? sharedUrl
    }

    private var iconName: String {
        switch reason {
        case .signedOut, .expired: return "lock.fill"
        case .banned: return "exclamationmark.triangle.fill"
        }
    }

    private var headline: String {
        switch reason {
        case .signedOut: return "로그인이 필요해요"
        case .expired: return "다시 로그인해 주세요"
        case .banned: return "정지된 계정이에요"
        }
    }

    private var message: String {
        switch reason {
        case .signedOut:
            return "MySaver 앱에서 로그인하면\n공유한 링크를 저장할 수 있어요."
        case .expired:
            return "로그인 정보가 만료됐어요.\n앱에서 다시 로그인하면 저장돼요."
        case .banned:
            return "이 계정으로는 저장할 수 없어요.\n자세한 내용은 앱에서 확인해 주세요."
        }
    }

    private var ctaLabel: String {
        switch reason {
        case .signedOut, .expired: return "MySaver 앱에서 로그인"
        case .banned: return "MySaver 앱 열기"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            dragHandle
            closeRow

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color(.systemGray6))
                        .frame(width: 56, height: 56)
                    Image(systemName: iconName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 6) {
                    Text(headline)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }

                linkChip
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 20)

            bottomBar
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Sections

    private var dragHandle: some View {
        HStack {
            Spacer()
            RoundedRectangle(cornerRadius: 99, style: .continuous)
                .fill(Color(.tertiaryLabel))
                .frame(width: 36, height: 4)
            Spacer()
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var closeRow: some View {
        HStack {
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            .accessibilityLabel("닫기")
        }
        .padding(.trailing, 8)
    }

    private var linkChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "link")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(domain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
        .clipShape(Capsule())
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            Button(action: onOpenMainApp) {
                Text(ctaLabel)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(.systemBackground))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color(.label))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Button(action: onClose) {
                Text("나중에 하기")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}
