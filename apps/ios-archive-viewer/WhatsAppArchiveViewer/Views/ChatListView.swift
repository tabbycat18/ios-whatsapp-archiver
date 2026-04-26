import SwiftUI
import UniformTypeIdentifiers

struct ChatListView: View {
    @EnvironmentObject private var store: ArchiveStore
    @State private var isImporterPresented = false
    @State private var searchText = ""

    private var filteredChats: [ChatSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return store.chats
        }
        return store.chats.filter { chat in
            chat.searchableTitle.localizedStandardContains(query)
        }
    }

    var body: some View {
        NavigationSplitView {
            Group {
                if store.chats.isEmpty {
                    ContentUnavailableView {
                        Label("No Archive Open", systemImage: "folder")
                    } actions: {
                        Button {
                            isImporterPresented = true
                        } label: {
                            Label("Open Archive", systemImage: "folder.badge.plus")
                        }
                    }
                } else {
                    List(selection: $store.selectedChat) {
                        ForEach(filteredChats) { chat in
                            NavigationLink(value: chat) {
                                ChatRowView(chat: chat)
                            }
                        }
                    }
                }
            }
            .navigationTitle(store.archiveName)
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search chats")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label("Open Archive", systemImage: "folder")
                    }
                }
            }
        } detail: {
            if let chat = store.selectedChat {
                MessageListView(
                    chat: chat,
                    messages: store.messages,
                    isLoadingOlder: store.isLoadingOlder,
                    hasMoreOlderMessages: store.hasMoreOlderMessages,
                    olderMessagesErrorMessage: store.olderMessagesErrorMessage,
                    initialMessageLoadGeneration: store.initialMessageLoadGeneration,
                    onLoadOlderMessages: store.loadOlderMessages
                )
            } else {
                ContentUnavailableView("Select a Chat", systemImage: "message")
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.folder, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                store.openPickedURL(url)
            case .failure(let error):
                store.errorMessage = error.localizedDescription
            }
        }
        .alert(
            "Archive Error",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .onAppear {
            store.loadDefaultArchiveIfAvailable()
        }
        .onChange(of: store.selectedChat) { _, chat in
            if let chat {
                store.loadMessages(for: chat)
            }
        }
    }
}

private struct ChatRowView: View {
    let chat: ChatSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(chat.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(chat.latestMessageDate.map(Self.dateFormatter.string(from:)) ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(chat.detailText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
