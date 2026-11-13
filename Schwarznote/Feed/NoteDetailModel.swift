//
//  NoteDetailModel.swift
//  Schwarznote
//

import Foundation
import Observation

/// State of one open note: detail, comments, and the like / collect / comment actions.
/// Actions update the screen first and roll back if the server refuses.
@Observable
final class NoteDetailModel {
    let note: Note
    private(set) var detail: NoteDetail?
    private(set) var loadError: String?
    /// Shown as an alert when an action fails.
    var actionError: String?
    let comments = Pager<Comment>()

    private var xsecToken: String { note.xsecToken ?? "" }

    init(note: Note) {
        self.note = note
    }

    func load(client: XHSClient) async {
        do {
            detail = try await client.noteDetail(id: note.id, xsecToken: xsecToken)
        } catch {
            loadError = error.localizedDescription
        }
        let id = note.id
        let token = xsecToken
        await comments.reset { cursor, _ in
            try await client.comments(noteID: id, xsecToken: token, cursor: cursor)
        }
    }

    func toggleLike(client: XHSClient) async {
        guard let before = detail else { return }
        let liked = !before.liked
        detail?.liked = liked
        detail?.likes = before.likes.adjustedCount(by: liked ? 1 : -1)
        do {
            try await client.setLiked(liked, noteID: note.id)
        } catch {
            detail = before
            actionError = error.localizedDescription
        }
    }

    func toggleCollect(client: XHSClient) async {
        guard let before = detail else { return }
        let collected = !before.collected
        detail?.collected = collected
        detail?.collects = before.collects.adjustedCount(by: collected ? 1 : -1)
        do {
            try await client.setCollected(collected, noteID: note.id)
        } catch {
            detail = before
            actionError = error.localizedDescription
        }
    }

    func toggleLike(of comment: Comment, client: XHSClient) async {
        let liked = !comment.liked
        editComment(comment.id) {
            $0.liked = liked
            $0.likes = comment.likes.adjustedCount(by: liked ? 1 : -1)
        }
        do {
            try await client.setCommentLiked(liked, noteID: note.id, commentID: comment.id)
        } catch {
            editComment(comment.id) {
                $0.liked = comment.liked
                $0.likes = comment.likes
            }
            actionError = error.localizedDescription
        }
    }

    /// Returns true when the comment was posted.
    func post(_ text: String, replyingTo target: Comment?, client: XHSClient) async -> Bool {
        do {
            let comment = try await client.postComment(noteID: note.id, content: text, replyTo: target?.id)
            if let target {
                comments.update(rootID(of: target.id)) { $0.replies.append(comment) }
            } else {
                comments.prepend(comment)
            }
            detail?.commentCount = detail?.commentCount.adjustedCount(by: 1) ?? "1"
            return true
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }

    func loadMoreReplies(for root: Comment, client: XHSClient) async {
        do {
            let page = try await client.replies(
                noteID: note.id, rootID: root.id, xsecToken: xsecToken, cursor: root.repliesCursor
            )
            comments.update(root.id) { root in
                let known = Set(root.replies.map(\.id))
                root.replies += page.comments.filter { !known.contains($0.id) }
                root.repliesCursor = page.cursor
                root.hasMoreReplies = page.hasMore
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// The top-level comment that is `id` or contains it as a reply.
    private func rootID(of id: String) -> String {
        comments.items.first { $0.id == id || $0.replies.contains { $0.id == id } }?.id ?? id
    }

    private func editComment(_ id: String, _ change: (inout Comment) -> Void) {
        comments.update(rootID(of: id)) { root in
            if root.id == id {
                change(&root)
            } else if let index = root.replies.firstIndex(where: { $0.id == id }) {
                change(&root.replies[index])
            }
        }
    }
}
