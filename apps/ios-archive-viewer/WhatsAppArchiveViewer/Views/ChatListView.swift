import SwiftUI
import UniformTypeIdentifiers
import ImageIO

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
                            Section("Stories") {
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
    @State private var isInstructionsPresented = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    InstructionsCardView {
                        isInstructionsPresented = true
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                }

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
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                    }
                } footer: {
                    Text("Labels are saved only in this app. Removing a saved archive record does not delete its files.")
                }

                Section {
                    DemoArchiveCardView(
                        isOpening: store.openingArchiveID == ArchiveStore.demoArchiveID,
                        isDisabled: store.isOpeningArchive,
                        onOpen: store.openDemoArchive
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("WhatsApp Archiver")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isInstructionsPresented = true
                    } label: {
                        Label("Help", systemImage: "questionmark.circle")
                    }
                }
            }
            .sheet(isPresented: $isInstructionsPresented) {
                ArchiveInstructionsView()
            }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconBackground)

                    Image(systemName: needsRelink ? "exclamationmark.triangle.fill" : kind.systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(needsRelink ? .orange : .accentColor)
                        .overlay {
                            if isOpening {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
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
        .padding(12)
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
            ArchiveActionButton(
                title: "Add",
                systemImage: "folder.badge.plus",
                style: .primary,
                maxWidth: .infinity,
                action: onAdd
            )
            .disabled(!canAdd)
        } else {
            HStack(spacing: 8) {
                ArchiveIconActionButton(
                    accessibilityTitle: isOpening ? "Opening" : "Open",
                    systemImage: "arrow.right.circle.fill",
                    showsProgress: isOpening,
                    action: onOpen
                )

                ArchiveActionButton(
                    title: "Relink",
                    systemImage: "link",
                    style: .secondary,
                    width: 96,
                    action: onRelink
                )
                .disabled(isOpening)

                Menu {
                    Button(action: onRename) {
                        Label("Rename", systemImage: "pencil")
                    }

                    Button(role: .destructive, action: onRemove) {
                        Label("Remove", systemImage: "trash")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "ellipsis.circle")
                        Text("More")
                            .lineLimit(1)
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 82)
                    .frame(minHeight: ArchiveActionButton.height)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(isOpening)
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

private struct InstructionsCardView: View {
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.tertiarySystemGroupedBackground))

                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text("How It Works")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("Backup, extract, transfer, and browse your archive locally.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onOpen) {
                Text("Help")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .frame(minWidth: 64, minHeight: ArchiveActionButton.height)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.quaternary)
        )
    }
}

private struct DemoArchiveCardView: View {
    let isOpening: Bool
    let isDisabled: Bool
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.blue.opacity(0.12))

                    Image(systemName: "sparkles")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.blue)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Demo Archive")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("Synthetic sample chats and media bundled with the app.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            ArchiveActionButton(
                title: isOpening ? "Opening" : "Try Demo Archive",
                systemImage: isOpening ? nil : "play.circle.fill",
                showsProgress: isOpening,
                style: .secondary,
                maxWidth: .infinity,
                action: onOpen
            )
            .disabled(isDisabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.quaternary)
        )
    }
}

private struct ArchiveIconActionButton: View {
    let accessibilityTitle: String
    let systemImage: String
    var showsProgress = false
    let action: () -> Void

    var body: some View {
        Button {
            guard !showsProgress else { return }
            action()
        } label: {
            Group {
                if showsProgress {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .frame(width: 72)
            .frame(minHeight: ArchiveActionButton.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .tint(.green)
        .accessibilityLabel(accessibilityTitle)
        .allowsHitTesting(!showsProgress)
    }
}

private struct ArchiveActionButton: View {
    enum Style {
        case primary
        case secondary
    }

    static let height: CGFloat = 38

    let title: String
    var systemImage: String?
    var showsProgress = false
    var style: Style
    var width: CGFloat?
    var maxWidth: CGFloat?
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            HStack(spacing: 7) {
                if showsProgress {
                    ProgressView()
                        .controlSize(.small)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }

                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .font(.subheadline.weight(.semibold))
            .frame(width: width)
            .frame(maxWidth: maxWidth)
            .frame(minHeight: Self.height)
            .contentShape(Rectangle())
        }

        switch style {
        case .primary:
            button
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(.green)
        case .secondary:
            button
                .buttonStyle(.bordered)
                .controlSize(.regular)
        }
    }
}

private struct ArchiveInstructionsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                InstructionSection(
                    title: "Quick Start",
                    systemImage: "iphone",
                    rows: [
                        "Make an encrypted local iPhone backup on your Mac.",
                        "Run the extractor script on the Mac.",
                        "Copy the extracted archive to your iPhone.",
                        "Open WhatsApp Archiver and add WhatsApp or WhatsApp Business.",
                        "Browse chats and media locally."
                    ]
                )

                InstructionSection(
                    title: "Detailed Steps",
                    systemImage: "folder",
                    rows: [
                        "In Finder, select your iPhone and choose a local backup.",
                        "Enable encrypted backup and keep the backup password.",
                        "Run the extractor from this project on the Mac.",
                        "The archive usually contains ChatStorage.sqlite, ContactsV2.sqlite, Media/, and Message/.",
                        "Transfer the extracted archive folder to the iPhone, then add it in the app."
                    ]
                )

                InstructionSection(
                    title: "Transfer Notes",
                    systemImage: "arrow.triangle.2.circlepath",
                    rows: [
                        "Real archives can be tens of GB and contain many files.",
                        "AirDrop and Files transfers can be slow for large archives.",
                        "iCloud Drive is user-managed and may keep syncing in the background.",
                        "Zip or package transfer is experimental until the app supports it directly.",
                        "Keep the Mac copy until the archive opens correctly on iPhone."
                    ]
                )

                InstructionSection(
                    title: "Privacy Notes",
                    systemImage: "shield",
                    rows: [
                        "The app reads local files in place.",
                        "This project has no server and does not upload archives.",
                        "Third-party transfer services are outside this project.",
                        "Removing a saved archive record does not delete archive files."
                    ]
                )

                InstructionSection(
                    title: "Demo Archive",
                    systemImage: "message",
                    rows: [
                        "Tap Try Demo Archive on the archive home screen to open bundled sample data.",
                        "The demo is fully synthetic and does not use a real archive slot.",
                        "Developers can also select test-fixtures/demo-archive/ through the normal Add flow."
                    ]
                )

                InstructionSection(
                    title: "Installation Status",
                    systemImage: "lock",
                    rows: [
                        "The source code is on GitHub.",
                        "Current installation still requires Xcode or developer/test distribution.",
                        "GitHub alone is not a universal one-tap iPhone install path.",
                        "Future options may include TestFlight, App Store, EU alternative distribution, or Web Distribution if requirements are met."
                    ]
                )
            }
            .navigationTitle("Instructions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct InstructionSection: View {
    let title: String
    let systemImage: String
    let rows: [String]

    var body: some View {
        Section {
            ForEach(rows, id: \.self) { row in
                Label {
                    Text(row)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label(title, systemImage: systemImage)
        }
    }
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
            ChatAvatarView(title: chat.title, imageURL: chat.profilePhotoURL)

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
    let imageURL: URL?
    @State private var image: CGImage?
    @State private var didFailImageLoad = false
    @State private var loadedImageURL: URL?

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

            if let image {
                Image(decorative: image, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFill()
            } else if let initials {
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
        .clipShape(Circle())
        .task(id: imageURL) {
            await loadImageIfNeeded()
        }
        .accessibilityHidden(true)
    }

    private func loadImageIfNeeded() async {
        if loadedImageURL != imageURL {
            image = nil
            didFailImageLoad = false
            loadedImageURL = imageURL
        }

        guard image == nil, !didFailImageLoad, let imageURL else {
            return
        }

        let loadedImage = await Task.detached(priority: .utility) {
            downsampleAvatarImage(at: imageURL, maxPixelSize: 120)
        }.value

        if let loadedImage {
            image = loadedImage
        } else {
            didFailImageLoad = true
        }
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

private func downsampleAvatarImage(at url: URL, maxPixelSize: CGFloat) -> CGImage? {
    let options = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else {
        return nil
    }

    let downsampleOptions = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ] as CFDictionary

    return CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions)
}
