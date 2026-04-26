import SwiftUI

struct MessageListView: View {
    let chat: ChatSummary
    let messages: [MessageRow]
    let isLoadingOlder: Bool
    let hasMoreOlderMessages: Bool
    let olderMessagesErrorMessage: String?
    let initialMessageLoadGeneration: Int
    let onLoadOlderMessages: () -> Void
    @State private var latestScrolledGeneration: Int?
    @State private var didCompleteInitialScroll = false
    @State private var lastOlderLoadTriggerMessageID: Int64?
    private let olderLoadThreshold = 8

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                List {
                    olderPaginationStatus

                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        MessageBubbleView(message: message, isGroupChat: chat.isGroupChat)
                            .id(message.id)
                            .listRowSeparator(.hidden)
                            .onAppear {
                                loadOlderMessagesIfNeeded(appearingAt: index)
                            }
                    }
                }
                .listStyle(.plain)
                .onAppear {
                    scrollToLatestMessageIfNeeded(using: proxy, animated: false)
                }
                .onChange(of: initialMessageLoadGeneration) { _, _ in
                    didCompleteInitialScroll = false
                    lastOlderLoadTriggerMessageID = nil
                    scrollToLatestMessageIfNeeded(using: proxy, animated: false)
                }
            }
        }
        .navigationTitle(chat.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private var olderPaginationStatus: some View {
        if isLoadingOlder || olderMessagesErrorMessage != nil {
            HStack(spacing: 8) {
                Spacer(minLength: 0)

                if isLoadingOlder {
                    ProgressView()
                        .controlSize(.small)
                }

                if let olderMessagesErrorMessage, !olderMessagesErrorMessage.isEmpty {
                    Text(olderMessagesErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                } else if isLoadingOlder {
                    Text("Loading older messages...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .listRowSeparator(.hidden)
        }
    }

    private func scrollToLatestMessageIfNeeded(using proxy: ScrollViewProxy, animated: Bool) {
        guard latestScrolledGeneration != initialMessageLoadGeneration else { return }
        latestScrolledGeneration = initialMessageLoadGeneration
        guard let latestMessageID = messages.last?.id else { return }
        DispatchQueue.main.async {
            if animated {
                withAnimation {
                    proxy.scrollTo(latestMessageID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(latestMessageID, anchor: .bottom)
            }
            didCompleteInitialScroll = true
        }
    }

    private func loadOlderMessagesIfNeeded(appearingAt index: Int) {
        guard didCompleteInitialScroll, hasMoreOlderMessages, !isLoadingOlder else { return }
        guard index < olderLoadThreshold else { return }
        guard let oldestMessageID = messages.first?.id else { return }
        guard lastOlderLoadTriggerMessageID != oldestMessageID else { return }
        lastOlderLoadTriggerMessageID = oldestMessageID
        onLoadOlderMessages()
    }
}

private struct MessageBubbleView: View {
    let message: MessageRow
    let isGroupChat: Bool

    var body: some View {
        HStack {
            if message.isFromMe {
                Spacer(minLength: 36)
            }

            VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 4) {
                if let senderLabel {
                    Text(senderLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(displayText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(message.isFromMe ? Color.green.opacity(0.18) : Color.gray.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .textSelection(.enabled)

                if let messageDate = message.messageDate {
                    Text(Self.dateFormatter.string(from: messageDate))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if !message.isFromMe {
                Spacer(minLength: 36)
            }
        }
        .padding(.vertical, 3)
    }

    private var senderLabel: String? {
        if message.isFromMe {
            return "You"
        }
        if isGroupChat {
            return message.friendlySenderName ?? "Unknown sender"
        }
        return nil
    }

    private var displayText: String {
        guard let text = message.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            if let media = message.media {
                return media.kind.placeholderText
            }
            return "Message not supported yet"
        }
        return text
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
