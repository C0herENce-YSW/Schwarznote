//
//  ChatModel.swift
//  Schwarznote
//

import Foundation
import Observation

/// One conversation's messages, oldest first. Loads the latest page, then earlier pages on demand.
@Observable
final class ChatModel {
    let chat: Chat
    private(set) var messages: [ChatMessage] = []
    private(set) var isLoading = false
    private(set) var reachedStart = false
    private(set) var error: String?

    private let client: XHSClient
    private let pageSize = 30

    init(chat: Chat, client: XHSClient) {
        self.chat = chat
        self.client = client
    }

    /// Messages the signed-in user sent. In a one-to-one chat the other side is `chat.id`.
    func isMine(_ message: ChatMessage) -> Bool {
        message.senderID != chat.id
    }

    func loadLatest() async {
        error = nil
        reachedStart = false
        messages = []
        await load(lastStoreID: chat.maxStoreID)
    }

    func loadEarlier() async {
        guard !isLoading, !reachedStart, let oldest = messages.first else { return }
        guard oldest.storeID > 1 else { reachedStart = true; return }
        await load(lastStoreID: oldest.storeID - 1)
    }

    private func load(lastStoreID: Int) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await client.chatMessages(userID: chat.id, lastStoreID: lastStoreID, limit: pageSize)
            let known = Set(messages.map(\.id))
            messages.insert(contentsOf: page.filter { !known.contains($0.id) }, at: 0)
            if page.count < pageSize { reachedStart = true }
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            self.error = error.localizedDescription
        }
    }
}
