//
//  FolderPickerSheet.swift
//  MySaverShare
//
//  ShareSheetView 의 📁 버튼 탭 시 표시되는 폴더 선택 시트.
//

import SwiftUI

struct FolderPickerSheet: View {

    let folders: [FolderInfo]
    let selectedId: Int?
    let onPick: (FolderInfo?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            handle
            header
            if folders.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        clearRow
                        ForEach(folders) { folder in
                            folderRow(folder)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Color(.systemBackground))
    }

    private var handle: some View {
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

    private var header: some View {
        HStack {
            Text("폴더 선택")
                .font(.system(size: 15, weight: .bold))
            Spacer()
            Button("취소") { onPick(nil) }
                .font(.system(size: 13))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("📁")
                .font(.system(size: 36))
            Text("폴더가 없습니다")
                .font(.system(size: 13, weight: .semibold))
            Text("앱에서 폴더를 생성 후 이용해주세요")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var clearRow: some View {
        Button {
            onPick(nil)
        } label: {
            HStack(spacing: 12) {
                Text("∅")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                Text("폴더 없이 저장")
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                Spacer()
                if selectedId == nil {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private func folderRow(_ folder: FolderInfo) -> some View {
        Button {
            onPick(folder)
        } label: {
            HStack(spacing: 12) {
                Text(folder.emoji ?? "📁")
                    .font(.system(size: 18))
                Text(folder.name)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                Spacer()
                if selectedId == folder.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }
}
