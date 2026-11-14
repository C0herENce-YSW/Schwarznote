//
//  UserProfileView.swift
//  Schwarznote
//

import SwiftUI

/// Someone's profile, opened from a note: avatar, bio, counts and follow button on top,
/// their notes in a grid below.
struct UserProfileView: View {
    @Environment(AuthModel.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let model: UserProfileModel
    @State private var selectedNote: Note?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 40), count: 5)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 50) {
                header
                    .focusSection()

                if model.notes.items.isEmpty, let error = model.notes.error {
                    ErrorView(message: error) { await model.notes.retry() }
                } else if model.notes.items.isEmpty, !model.notes.isLoading {
                    Text("还没有发布笔记")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 80)
                }

                LazyVGrid(columns: columns, spacing: 50) {
                    ForEach(model.notes.items) { note in
                        Button {
                            selectedNote = note
                        } label: {
                            NoteCard(note: note)
                        }
                        .buttonStyle(.card)
                        .task { await model.notes.loadMoreIfNeeded(current: note) }
                    }
                }

                if model.notes.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 60)
        }
        .background(.background)
        .onExitCommand { dismiss() }
        .task { await model.load(client: auth.client) }
        .fullScreenCover(item: $selectedNote) { note in
            NoteDetailView(note: note, xsecSource: "pc_user")
        }
        .alert("操作失败", isPresented: Binding(
            get: { model.actionError != nil },
            set: { if !$0 { model.actionError = nil } }
        )) {
            Button("好") {}
        } message: {
            Text(model.actionError ?? "")
        }
    }

    private var author: Author { model.author }

    private var header: some View {
        HStack(alignment: .top, spacing: 50) {
            AvatarView(
                author: Author(id: author.id, nickname: model.profile?.nickname ?? author.nickname,
                               avatarURL: model.profile?.avatarURL ?? author.avatarURL),
                size: 180
            )

            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 30) {
                    Text(model.profile?.nickname ?? author.nickname)
                        .font(.largeTitle.bold())
                    if author.id != auth.currentUser?.userId {
                        FollowButton(relation: model.relation, nickname: author.nickname) { following in
                            guard auth.isLoggedIn else {
                                model.actionError = "请先在“我”页面扫码登录"
                                return
                            }
                            Task { await model.setFollowing(following, client: auth.client) }
                        }
                    }
                }

                if let profile = model.profile {
                    let ids = [profile.redID.map { "小红书号：\($0)" }, profile.ipLocation.map { "IP属地：\($0)" }]
                        .compactMap { $0 }
                    if !ids.isEmpty {
                        Text(ids.joined(separator: "  ·  "))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if !profile.bio.isEmpty {
                        Text(profile.bio)
                            .font(.callout)
                            .lineLimit(4)
                    }
                    HStack(spacing: 50) {
                        ForEach(profile.stats, id: \.self) { stat in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(stat.count).font(.headline)
                                Text(stat.name).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                } else if let error = model.loadError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 关注 / 回关 when not following; 已关注 / 互相关注 when following, which asks before unfollowing.
struct FollowButton: View {
    let relation: FollowRelation
    let nickname: String
    /// Called with true to follow, false to unfollow.
    let onChange: (Bool) -> Void
    @State private var confirmingUnfollow = false

    var body: some View {
        Button {
            if relation.isFollowing {
                confirmingUnfollow = true
            } else {
                onChange(true)
            }
        } label: {
            Text(relation.title)
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 10)
        }
        .buttonStyle(FollowStyle(isFollowing: relation.isFollowing))
        .confirmationDialog("不再关注\(nickname)？", isPresented: $confirmingUnfollow, titleVisibility: .visible) {
            Button("不再关注", role: .destructive) { onChange(false) }
            Button("取消", role: .cancel) {}
        }
    }
}

/// Filled with the accent color until followed, then a quiet outline, like the web.
private struct FollowStyle: ButtonStyle {
    let isFollowing: Bool
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 12)
            .padding(.horizontal, 22)
            .foregroundStyle(isFocused ? Color.black : (isFollowing ? Color.secondary : Color.white))
            .background {
                if isFocused {
                    Capsule().fill(Color.white)
                } else if isFollowing {
                    Capsule().strokeBorder(Color.secondary.opacity(0.6), lineWidth: 2)
                } else {
                    Capsule().fill(Color.accentColor)
                }
            }
            .scaleEffect(isFocused ? 1.1 : (configuration.isPressed ? 0.95 : 1))
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}
