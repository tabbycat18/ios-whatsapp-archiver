import SwiftUI
import UniformTypeIdentifiers
import ImageIO
import UIKit

struct ChatListView: View {
    @EnvironmentObject private var store: ArchiveStore
    @State private var isImporterPresented = false
    @State private var importMode: ArchiveImportMode = .add(.whatsApp)
    @State private var searchText = ""
    @State private var isWallpaperSettingsPresented = false

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
        filteredChats.filter { chat in
            chat.classification == .normalConversation || chat.classification == .separateConversation
        }
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
        .onChange(of: store.selectedChat?.id) { _, _ in
            guard let chat = store.selectedChat else { return }
            store.loadMessages(for: chat)
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

                ToolbarItem(placement: .secondaryAction) {
                    ContactNameToolbarMenu(resolver: store.contactNameResolver)
                }

                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        isWallpaperSettingsPresented = true
                    } label: {
                        Label("Wallpaper", systemImage: "paintpalette")
                    }
                }
            }
            .sheet(isPresented: $isWallpaperSettingsPresented) {
                WallpaperSettingsView(
                    selectedTheme: $store.wallpaperTheme,
                    archiveWallpaperAvailable: store.wallpaperURL != nil
                )
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
                    wallpaperTheme: store.wallpaperTheme,
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

private struct WallpaperSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedTheme: ChatWallpaperTheme
    let archiveWallpaperAvailable: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ChatWallpaperTheme.allCases) { theme in
                        Button {
                            selectedTheme = theme
                        } label: {
                            HStack(spacing: 12) {
                                WallpaperThemeThumbnail(
                                    theme: theme,
                                    archiveWallpaperAvailable: archiveWallpaperAvailable
                                )

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(theme.displayName)
                                        .font(.body)
                                        .foregroundStyle(.primary)

                                    Text(theme.detailText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer(minLength: 8)

                                if selectedTheme == theme {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Archive Default uses the selected archive's wallpaper file when available. Other choices are generated by the app and do not edit or copy archive files.")
                }
            }
            .navigationTitle("Wallpaper")
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

private struct WallpaperThemeThumbnail: View {
    @Environment(\.colorScheme) private var colorScheme
    let theme: ChatWallpaperTheme
    let archiveWallpaperAvailable: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(background)

            switch theme {
            case .archiveDefault:
                Image(systemName: archiveWallpaperAvailable ? "photo.on.rectangle" : "folder")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            case .plain:
                Image(systemName: "rectangle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            case .classic, .softPattern, .demo:
                ProceduralChatWallpaperView(theme: theme)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .frame(width: 58, height: 42)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        }
    }

    private var background: Color {
        switch (theme, colorScheme == .dark) {
        case (.archiveDefault, true):
            return Color(red: 0.14, green: 0.15, blue: 0.15)
        case (.archiveDefault, false):
            return Color(red: 0.88, green: 0.89, blue: 0.86)
        case (.classic, true):
            return Color(red: 0.10, green: 0.16, blue: 0.14)
        case (.classic, false):
            return Color(red: 0.88, green: 0.91, blue: 0.85)
        case (.softPattern, true):
            return Color(red: 0.13, green: 0.14, blue: 0.15)
        case (.softPattern, false):
            return Color(red: 0.91, green: 0.92, blue: 0.91)
        case (.demo, true):
            return Color(red: 0.12, green: 0.13, blue: 0.12)
        case (.demo, false):
            return Color(red: 0.88, green: 0.89, blue: 0.82)
        case (.plain, true):
            return Color(red: 0.05, green: 0.05, blue: 0.06)
        case (.plain, false):
            return Color(red: 0.98, green: 0.98, blue: 0.99)
        }
    }
}

private struct ContactNameToolbarMenu: View {
    @ObservedObject var resolver: ContactNameResolver
    @Environment(\.openURL) private var openURL

    var body: some View {
        Menu {
            Section {
                Label(resolver.status.displayText, systemImage: statusImageName)
                Text(resolver.status.explanation)
            }

            Section {
                if resolver.status == .enabled || resolver.status == .loading {
                    Button(role: .destructive) {
                        resolver.disableContactMatching()
                    } label: {
                        Label("Stop Using iPhone Contacts", systemImage: "person.crop.circle.badge.xmark")
                    }
                } else {
                    Button {
                        resolver.enableContactMatching()
                    } label: {
                        Label("Use iPhone Contacts", systemImage: "person.crop.circle.badge.checkmark")
                    }
                    .disabled(resolver.status == .restricted)
                }

                if resolver.status == .permissionDenied {
                    Button {
                        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                            openURL(settingsURL)
                        }
                    } label: {
                        Label("Open iOS Settings", systemImage: "gear")
                    }
                }
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }

    private var statusImageName: String {
        switch resolver.status {
        case .notEnabled:
            return "person.crop.circle.badge.questionmark"
        case .loading:
            return "person.crop.circle.badge.clock"
        case .enabled:
            return "person.crop.circle.badge.checkmark"
        case .permissionDenied, .restricted:
            return "person.crop.circle.badge.exclamationmark"
        }
    }
}

private struct ArchiveLibraryView: View {
    @EnvironmentObject private var store: ArchiveStore
    let onAddArchive: (ArchiveKind) -> Void
    let onRelinkArchive: (SavedArchive) -> Void
    @State private var renameTarget: SavedArchive?
    @State private var renameText = ""
    @State private var isInstructionsPresented = false
    @State private var isWallpaperSettingsPresented = false

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
            .navigationTitle("WA Archiver")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isInstructionsPresented = true
                    } label: {
                        Label("Help", systemImage: "questionmark.circle")
                    }
                }

                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        isWallpaperSettingsPresented = true
                    } label: {
                        Label("Wallpaper", systemImage: "paintpalette")
                    }
                }
            }
            .sheet(isPresented: $isInstructionsPresented) {
                ArchiveInstructionsView()
            }
            .sheet(isPresented: $isWallpaperSettingsPresented) {
                WallpaperSettingsView(
                    selectedTheme: $store.wallpaperTheme,
                    archiveWallpaperAvailable: store.wallpaperURL != nil
                )
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)

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
                    width: 116,
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
                    ArchiveActionPillLabel(
                        title: "More",
                        systemImage: "ellipsis.circle",
                        style: .secondary,
                        width: 104
                    )
                }
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
            ArchiveActionPillLabel(
                title: nil,
                systemImage: systemImage,
                showsProgress: showsProgress,
                style: .primary,
                width: 72
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityTitle)
        .allowsHitTesting(!showsProgress)
    }
}

private struct ArchiveActionButton: View {
    @Environment(\.isEnabled) private var isEnabled

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
        Button(action: action) {
            ArchiveActionPillLabel(
                title: title,
                systemImage: systemImage,
                showsProgress: showsProgress,
                style: style,
                width: width,
                maxWidth: maxWidth
            )
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(title)
    }
}

private struct ArchiveActionPillLabel: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String?
    var systemImage: String?
    var showsProgress = false
    let style: ArchiveActionButton.Style
    var width: CGFloat?
    var maxWidth: CGFloat?

    var body: some View {
        HStack(spacing: title == nil ? 0 : 7) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .tint(foregroundColor)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
            }

            if let title {
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(foregroundColor)
        .frame(width: width)
        .frame(maxWidth: maxWidth)
        .frame(height: ArchiveActionButton.height)
        .background(backgroundColor, in: Capsule(style: .continuous))
        .contentShape(Capsule(style: .continuous))
    }

    private var foregroundColor: Color {
        switch style {
        case .primary:
            return .white
        case .secondary:
            return .accentColor
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary:
            return .green
        case .secondary:
            return colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.07)
        }
    }
}

private struct ArchiveInstructionsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    InstructionIntroCard()

                    InstructionStepsCard(
                        steps: [
                            "Create an encrypted local iPhone backup on your Mac.",
                            "Run the extractor from this project.",
                            "Transfer the whole extracted archive folder to your iPhone.",
                            "Add the whole folder in WA Archiver and browse locally."
                        ]
                    )

                    InstructionInfoSection(
                        title: "Archive Folder",
                        systemImage: "folder",
                        rows: [
                            InstructionInfoRow(
                                title: "What to select",
                                text: "Choose the whole extracted folder. It must contain ChatStorage.sqlite; ContactsV2.sqlite, Media/, and Message/ are used automatically when present."
                            ),
                            InstructionInfoRow(
                                title: "Large archives",
                                text: "Real exports can be tens of GB. Keep the Mac copy until the archive opens correctly on iPhone."
                            )
                        ]
                    )

                    InstructionInfoSection(
                        title: "Privacy",
                        systemImage: "shield",
                        rows: [
                            InstructionInfoRow(
                                title: "Local only",
                                text: "The app reads selected files in place and does not upload archives."
                            ),
                            InstructionInfoRow(
                                title: "Saved records",
                                text: "Removing an archive record only removes the app shortcut; it does not delete archive files."
                            )
                        ]
                    )

                    InstructionInfoSection(
                        title: "Demo and Install",
                        systemImage: "info.circle",
                        rows: [
                            InstructionInfoRow(
                                title: "Demo archive",
                                text: "Try Demo Archive opens bundled synthetic sample data and does not use a real archive slot."
                            ),
                            InstructionInfoRow(
                                title: "Distribution",
                                text: "Current installation still requires Xcode or developer/test distribution."
                            ),
                            InstructionInfoRow(
                                title: "Source code",
                                text: "Read setup notes and extractor documentation in the GitHub repository.",
                                url: URL(string: "https://github.com/tabbycat18/ios-whatsapp-archiver")
                            )
                        ]
                    )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Instructions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(.systemGroupedBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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

private struct InstructionIntroCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Read an iPhone WhatsApp archive locally", systemImage: "lock.doc")
                .font(.headline)

            Text("You need an encrypted Finder backup, the Mac extractor, and the extracted archive folder on your iPhone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct InstructionStepsCard: View {
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Basic Flow", systemImage: "list.number")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Color.green, in: Circle())

                        Text(step)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(18)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct InstructionInfoSection: View {
    let title: String
    let systemImage: String
    let rows: [InstructionInfoRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.title)
                            .font(.subheadline.weight(.semibold))

                        Text(row.text)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let url = row.url {
                            Link("Open GitHub repository", destination: url)
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 13)

                    if row.id != rows.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct InstructionInfoRow: Identifiable {
    var id: String { title }
    let title: String
    let text: String
    var url: URL?
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
            ChatAvatarView(chat: chat)

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
    let chat: ChatSummary
    @EnvironmentObject private var store: ArchiveStore
    @State private var image: CGImage?
    @State private var loadedAvatarID: String?

    private var initials: String? {
        Self.initials(from: chat.title)
    }

    private var paletteColor: Color {
        Self.palette[Self.paletteIndex(for: chat.title)]
    }

    private var avatarID: String {
        "\(chat.id)|\(chat.contactJID ?? "")|\(chat.contactIdentifier ?? "")|\(chat.profilePhotoIdentifiers.joined(separator: ","))"
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
        .task(id: avatarID) {
            await loadImageIfNeeded()
        }
        .accessibilityHidden(true)
    }

    private func loadImageIfNeeded() async {
        if loadedAvatarID != avatarID {
            image = nil
            loadedAvatarID = avatarID
        }

        guard image == nil else { return }
        if let loadedImage = await store.profileAvatarImage(for: chat) {
            guard !Task.isCancelled else { return }
            image = loadedImage
        } else {
            loadedAvatarID = avatarID
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

func downsampleAvatarImage(at url: URL, maxPixelSize: CGFloat) -> CGImage? {
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
