//
//  ShareSheetView.swift
//  MySaverShare
//
//  iOS Share Extension 메인 SwiftUI 뷰. 로그인 상태에서만 표시된다
//  (비로그인은 ShareLoginPromptView).
//  와이어프레임: 드래그핸들 / 썸네일 / 제목·메타 / 태그 / 노트 / 리마인드 / 바텀바
//

import SwiftUI

struct ShareSheetView: View {

    @ObservedObject var model: SharePreviewModel

    /// "추가하기" 성공/취소 시 호출 — ShareViewController.complete() 트리거.
    var onClose: () -> Void

    @State private var showFolderPicker: Bool = false
    @FocusState private var noteFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            dragHandle
            closeRow
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    thumbnailSection
                    titleSection
                    tagsSection
                    noteSection
                    reminderSection
                    Spacer(minLength: 12)
                }
            }
            .scrollDismissesKeyboard(.interactively)

            bottomBar
        }
        .background(Color(.systemBackground))
        .task {
            async let p: () = model.loadPreview()
            async let f: () = model.loadFolders()
            _ = await (p, f)
        }
        .sheet(isPresented: $showFolderPicker) {
            FolderPickerSheet(
                folders: model.folders,
                selectedId: model.selectedFolder?.id,
                onPick: { folder in
                    model.selectedFolder = folder
                    showFolderPicker = false
                }
            )
            .presentationDetents([.medium, .large])
        }
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

    @ViewBuilder
    private var thumbnailSection: some View {
        // Color.clear → aspectRatio → overlay 패턴.
        // AsyncImage 의 intrinsic content size 가 부모로 누수되어
        // share popup 이 가로로 늘어나는 현상 방지 — 크기는 먼저 확정하고 그 안에 그림.
        Color.clear
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: 200)
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(.systemGray5), Color(.systemGray4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    if let urlString = model.ogImageUrl, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            case .failure:
                                Image(systemName: "link")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.secondary)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else if model.isPreviewLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "link")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.displayTitle)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text("\(model.domain) · \(model.displayDate)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("태그")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            HStack(spacing: 6) {
                tagChip(text: "🔒 uncategorized", style: .uncategorized)
                tagChip(text: "＋ 태그 추가", style: .add)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var noteSection: some View {
        HStack(spacing: 8) {
            Text("📝")
                .font(.system(size: 13))
            TextField("노트 추가...", text: $model.note, axis: .vertical)
                .font(.system(size: 12))
                .focused($noteFieldFocused)
                .lineLimit(1...4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var reminderSection: some View {
        HStack {
            HStack(spacing: 7) {
                Circle()
                    .fill(Color(.systemGray4))
                    .frame(width: 7, height: 7)
                Text("리마인드 없음")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text("＋")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    let ok = await model.save()
                    if ok {
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        onClose()
                    }
                }
            } label: {
                Group {
                    if model.isSaving {
                        ProgressView()
                            .tint(Color(.systemBackground))
                    } else {
                        Text(ctaLabel)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(.systemBackground))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(model.isSaving ? Color(.systemGray) : Color(.label))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .disabled(model.isSaving)

            Button {
                showFolderPicker = true
            } label: {
                ZStack {
                    Circle()
                        .fill(Color(.systemGray6))
                        .frame(width: 34, height: 34)
                    Text(model.selectedFolder?.emoji ?? "📁")
                        .font(.system(size: 15))
                }
            }
            .accessibilityLabel("폴더 선택")

            Button {
                onClose()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color(.systemRed).opacity(0.12))
                        .frame(width: 34, height: 34)
                    Text("🗑")
                        .font(.system(size: 15))
                }
            }
            .accessibilityLabel("취소")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(Color(.systemGray6))
                .frame(height: 1),
            alignment: .top
        )
        .overlay(alignment: .top) {
            statusOverlay
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch model.saveStatus {
        case .success(let msg):
            Text("✓ \(msg)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.green)
                .padding(.top, 2)
                .transition(.opacity)
        case .failure(let msg):
            Text("⚠ \(msg)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.orange)
                .padding(.top, 2)
                .transition(.opacity)
        default:
            EmptyView()
        }
    }

    private var ctaLabel: String {
        if let folder = model.selectedFolder {
            return "‘\(folder.name)’에 추가하기"
        }
        return "추가하기"
    }

    // MARK: - Tag chip

    private enum ChipStyle { case uncategorized, add }

    private func tagChip(text: String, style: ChipStyle) -> some View {
        let (bg, fg): (Color, Color) = {
            switch style {
            case .uncategorized:
                return (Color(red: 254/255, green: 243/255, blue: 199/255), Color(red: 146/255, green: 64/255, blue: 14/255))
            case .add:
                return (Color(red: 220/255, green: 252/255, blue: 231/255), Color(red: 22/255, green: 101/255, blue: 52/255))
            }
        }()
        return Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(bg)
            .clipShape(Capsule())
    }
}
