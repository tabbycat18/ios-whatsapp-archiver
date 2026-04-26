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

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                List {
                    olderPaginationSentinel

                    Section {
                        ForEach(messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                                .listRowSeparator(.hidden)
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(chat.title)
                                .font(.headline)
                            Text(summaryText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .textCase(nil)
                        .padding(.vertical, 6)
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
    }

    @ViewBuilder
    private var olderPaginationSentinel: some View {
        VStack(spacing: 6) {
            if isLoadingOlder {
                ProgressView()
                    .controlSize(.small)
            }

            if let olderMessagesErrorMessage, !olderMessagesErrorMessage.isEmpty {
                Text(olderMessagesErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: isLoadingOlder || olderMessagesErrorMessage != nil ? 28 : 1)
        .listRowSeparator(.hidden)
        .onAppear(perform: loadOlderMessagesIfNeeded)
    }

    private var summaryText: String {
        if messages.count < chat.messageCount {
            return "Showing \(messages.count.formatted()) of \(chat.messageCount.formatted()) messages"
        }
        return "Showing \(messages.count.formatted()) messages"
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

    private func loadOlderMessagesIfNeeded() {
        guard didCompleteInitialScroll, hasMoreOlderMessages, !isLoadingOlder else { return }
        guard let oldestMessageID = messages.first?.id else { return }
        guard lastOlderLoadTriggerMessageID != oldestMessageID else { return }
        lastOlderLoadTriggerMessageID = oldestMessageID
        onLoadOlderMessages()
    }
}

private struct MessageBubbleView: View {
    let message: MessageRow

    var body: some View {
        HStack {
            if message.isFromMe {
                Spacer(minLength: 36)
            }

            VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 4) {
                Text(senderLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

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

    private var senderLabel: String {
        if message.isFromMe {
            return "You"
        }
        return message.pushName?.isEmpty == false ? message.pushName! : (message.senderJID ?? "Them")
    }

    private var displayText: String {
        guard let text = message.text, !text.isEmpty else {
            if let media = message.media {
                return media.kind.placeholderText
            }
            return "Unsupported message"
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
