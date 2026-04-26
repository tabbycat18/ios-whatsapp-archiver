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
            .navigationTitle("Chats")
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
                    wallpaperURL: store.wallpaperURL,
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
        HStack(spacing: 12) {
            ChatAvatarView(title: chat.title)

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
                    .lineLimit(1)
            }
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

private struct ChatAvatarView: View {
    let title: String

    private var initials: String? {
        Self.initials(from: title)
    }

    private var paletteColor: Color {
        Self.palette[Self.paletteIndex(for: title)]
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(paletteColor.gradient)

            if let initials {
                Text(initials)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }

    private static let palette: [Color] = [
        Color(red: 0.15, green: 0.48, blue: 0.74),
        Color(red: 0.22, green: 0.58, blue: 0.39),
        Color(red: 0.62, green: 0.36, blue: 0.13),
        Color(red: 0.68, green: 0.24, blue: 0.35),
        Color(red: 0.36, green: 0.33, blue: 0.69),
        Color(red: 0.22, green: 0.53, blue: 0.58)
    ]

    private static func initials(from title: String) -> String? {
        let letters = title
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .compactMap { word -> String? in
                guard let letter = word.first(where: \.isLetter) else { return nil }
                return String(letter)
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                    .uppercased()
            }
            .prefix(2)
            .joined()

        return letters.isEmpty ? nil : letters
    }

    private static func paletteIndex(for title: String) -> Int {
        let scalarTotal = title.unicodeScalars.reduce(0) { partialResult, scalar in
            partialResult + Int(scalar.value)
        }
        return abs(scalarTotal) % palette.count
    }
}
