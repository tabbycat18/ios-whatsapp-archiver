import SwiftUI
import UniformTypeIdentifiers

struct ChatListView: View {
    @EnvironmentObject private var store: ArchiveStore
    @State private var isImporterPresented = false
    @State private var importMode: ArchiveImportMode = .add(.whatsApp)
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

    private var filteredNormalChats: [ChatSummary] {
        filteredChats.filter { $0.classification != .statusStoryFragment }
    }

    private var filteredStatusStoryChats: [ChatSummary] {
        filteredChats.filter { $0.classification == .statusStoryFragment }
    }

    var body: some View {
        Group {
            if store.isArchiveOpen {
                chatNavigation
            } else {
                ArchiveLibraryView(
                    onAddArchive: presentAddArchive,
                    onRelinkArchive: presentRelinkArchive
                )
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
                switch importMode {
                case .add(let kind):
                    store.openPickedURL(url, kind: kind)
                case .relink(let id):
                    store.relinkArchive(id: id, with: url)
                }
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
        .onChange(of: store.selectedChat) { _, chat in
            if let chat {
                store.loadMessages(for: chat)
            }
        }
    }

    private var chatNavigation: some View {
        NavigationSplitView {
            Group {
                if store.chats.isEmpty {
                    ContentUnavailableView {
                        Label("No Archive Open", systemImage: "folder")
                    } actions: {
                        Button {
                            store.closeArchive()
                        } label: {
                            Label("Archives", systemImage: "archivebox")
                        }
                    }
                } else {
                    List(selection: $store.selectedChat) {
                        if !filteredStatusStoryChats.isEmpty {
                            Section("Stories / Status") {
                                ForEach(filteredStatusStoryChats) { chat in
                                    NavigationLink(value: chat) {
                                        ChatRowView(chat: chat)
                                    }
                                }
                            }
                        }

                        Section("Chats") {
                            ForEach(filteredNormalChats) { chat in
                                NavigationLink(value: chat) {
                                    ChatRowView(chat: chat)
                                }
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
                        store.closeArchive()
                    } label: {
                        Label("Archives", systemImage: "archivebox")
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
    }

    private func presentAddArchive(_ kind: ArchiveKind) {
        importMode = .add(kind)
        isImporterPresented = true
    }

    private func presentRelinkArchive(_ archive: SavedArchive) {
        importMode = .relink(archive.id)
        isImporterPresented = true
    }
}

private enum ArchiveImportMode {
    case add(ArchiveKind)
    case relink(UUID)
}

private struct ArchiveLibraryView: View {
    @EnvironmentObject private var store: ArchiveStore
    let onAddArchive: (ArchiveKind) -> Void
    let onRelinkArchive: (SavedArchive) -> Void
    @State private var renameTarget: SavedArchive?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ArchiveKind.allCases) { kind in
                        let archive = store.savedArchive(for: kind)
                        ArchiveSlotCardView(
                            kind: kind,
                            archive: archive,
                            needsRelink: archive.map { store.archivesNeedingRelink.contains($0.id) } ?? false,
                            isOpening: archive.map { store.openingArchiveID == $0.id } ?? false,
                            canAdd: archive == nil && !store.isOpeningArchive && store.savedArchives.count < ArchiveKind.allCases.count,
                            onOpen: {
                                guard let archive else { return }
                                store.openSavedArchive(archive)
                            },
                            onAdd: { onAddArchive(kind) },
                            onRelink: {
                                guard let archive else { return }
                                onRelinkArchive(archive)
                            },
                            onRename: {
                                guard let archive else { return }
                                renameTarget = archive
                                renameText = archive.displayName
                            },
                            onRemove: {
                                guard let archive else { return }
                                store.removeArchive(archive)
                            }
                        )
                        .disabled(store.isOpeningArchive && archive?.id != store.openingArchiveID)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                    }
                } footer: {
                    Text("Labels are saved only in this app. Removing a saved archive record does not delete its files.")
                }
            }
            .navigationTitle("iOS WhatsApp Archiver")
            .overlay(alignment: .bottom) {
                if store.isOpeningArchive {
                    ArchiveOpeningOverlay()
                        .padding(.bottom, 18)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .alert(
                "Rename Archive",
                isPresented: Binding(
                    get: { renameTarget != nil },
                    set: { if !$0 { renameTarget = nil } }
                )
            ) {
                TextField("Label", text: $renameText)
                Button("Save") {
                    if let renameTarget {
                        store.renameArchive(renameTarget, to: renameText)
                    }
                    renameTarget = nil
                }
                Button("Cancel", role: .cancel) {
                    renameTarget = nil
                }
            } message: {
                Text("This only changes the local label in this app.")
            }
        }
    }
}

private struct ArchiveSlotCardView: View {
    let kind: ArchiveKind
    let archive: SavedArchive?
    let needsRelink: Bool
    let isOpening: Bool
    let canAdd: Bool
    let onOpen: () -> Void
    let onAdd: () -> Void
    let onRelink: () -> Void
    let onRename: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconBackground)

                    Image(systemName: needsRelink ? "exclamationmark.triangle.fill" : kind.systemImage)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(needsRelink ? .orange : .accentColor)
                        .overlay {
                            if isOpening {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 5) {
                    Text(archive?.displayName ?? kind.defaultDisplayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(statusColor)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if needsRelink {
                        Text("Archive needs reselecting")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            actionButtons
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.quaternary)
        )
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var actionButtons: some View {
        if archive == nil {
            Button(action: onAdd) {
                Label("Add", systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.green)
            .disabled(!canAdd)
        } else {
            HStack(spacing: 10) {
                Button(action: onOpen) {
                    Label(isOpening ? "Opening" : "Open", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.green)
                .disabled(isOpening)

                Button(action: onRelink) {
                    Label("Relink", systemImage: "link")
                        .labelStyle(.iconOnly)
                        .frame(width: 42)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isOpening)
                .accessibilityLabel("Relink archive")

                Menu {
                    Button(action: onRename) {
                        Label("Rename", systemImage: "pencil")
                    }

                    Button(role: .destructive, action: onRemove) {
                        Label("Remove", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                        .frame(width: 42)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isOpening)
                .accessibilityLabel("More archive actions")
            }
        }
    }

    private var statusText: String {
        guard let archive else {
            return "Not added"
        }

        var components = ["Added"]
        if let chatCount = archive.chatCount {
            components.append("\(chatCount.formatted()) chats")
        }
        if let lastOpenedAt = archive.lastOpenedAt {
            components.append("Opened \(Self.relativeDateFormatter.localizedString(for: lastOpenedAt, relativeTo: Date()))")
        }
        return components.joined(separator: " • ")
    }

    private var statusColor: Color {
        if needsRelink {
            return .orange
        }
        return archive == nil ? .secondary : .primary
    }

    private var iconBackground: Color {
        needsRelink ? Color.orange.opacity(0.14) : Color.accentColor.opacity(0.12)
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

private struct ArchiveOpeningOverlay: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            Text("Opening archive")
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 8, y: 3)
        .accessibilityElement(children: .combine)
    }
}

private struct ChatRowView: View {
    let chat: ChatSummary

    var body: some View {
        HStack(spacing: 12) {
            ChatAvatarView(title: chat.title)

            VStack(alignment: .leading, spacing: 4) {
                Text(chat.title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(chat.detailText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            if let latestMessageDate = chat.latestMessageDate {
                let dateText = ChatListDateFormatter.shared.displayString(for: latestMessageDate)
                Text(dateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityLabel(dateText)
            }
        }
        .padding(.vertical, 4)
    }
}

private final class ChatListDateFormatter {
    static let shared = ChatListDateFormatter()

    private let calendar = Calendar.current
    private let lock = NSLock()
    private var displayCache: [String: String] = [:]

    func displayString(for date: Date, now: Date = Date()) -> String {
        let cacheKey = "\(Int(date.timeIntervalSince1970))|\(dayCacheKey(for: now))"
        lock.lock()
        if let cached = displayCache[cacheKey] {
            lock.unlock()
            return cached
        }

        let formatted = format(date, now: now)
        if displayCache.count > 4_096 {
            displayCache.removeAll(keepingCapacity: true)
        }
        displayCache[cacheKey] = formatted
        lock.unlock()
        return formatted
    }

    private func format(_ date: Date, now: Date) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return timeFormatter.string(from: date)
        }

        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }

        let startOfToday = calendar.startOfDay(for: now)
        let startOfDate = calendar.startOfDay(for: date)
        if let recentCutoff = calendar.date(byAdding: .day, value: -6, to: startOfToday),
           startOfDate >= recentCutoff,
           startOfDate < startOfToday {
            return weekdayFormatter.string(from: date)
        }

        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return dayMonthFormatter.string(from: date)
        }

        return dayMonthYearFormatter.string(from: date)
    }

    private func dayCacheKey(for date: Date) -> Int {
        calendar.ordinality(of: .day, in: .era, for: date) ?? 0
    }

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "E"
        return formatter
    }()

    private let dayMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd.MM"
        return formatter
    }()

    private let dayMonthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd.MM.yy"
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
