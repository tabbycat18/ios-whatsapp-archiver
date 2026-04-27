import SwiftUI
import UniformTypeIdentifiers
import Combine

enum ArchiveImportError: LocalizedError {
    case missingApplicationSupportDirectory
    case missingDatabase(URL)
    case missingDemoArchive
    case importFailed(String)
    case staleBookmark(String)
    case bookmarkResolutionFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingApplicationSupportDirectory:
            return "Could not locate the app's Application Support folder."
        case .missingDatabase:
            return "Missing ChatStorage.sqlite in the selected archive."
        case .missingDemoArchive:
            return "The bundled demo archive is missing from this build."
        case .importFailed(let message):
            return "Could not import archive: \(message)"
        case .staleBookmark(let archiveName):
            return "\(archiveName) needs reselecting because its saved file access is stale."
        case .bookmarkResolutionFailed(let archiveName):
            return "Could not reopen \(archiveName). Reselect the archive to relink it."
        }
    }
}

struct SavedArchive: Identifiable, Codable, Hashable {
    let id: UUID
    var displayName: String
    var archiveKind: String?
    var bookmarkData: Data
    var selectedResourceIsDirectory: Bool
    let createdAt: Date
    var lastOpenedAt: Date?
    var chatCount: Int?

    var kind: ArchiveKind? {
        get { ArchiveKind(storedValue: archiveKind) }
        set { archiveKind = newValue?.rawValue }
    }
}

enum ArchiveKind: String, Codable, CaseIterable, Identifiable {
    case whatsApp = "whatsApp"
    case whatsAppBusiness = "whatsAppBusiness"

    var id: String { rawValue }

    var defaultDisplayName: String {
        switch self {
        case .whatsApp:
            return "WhatsApp"
        case .whatsAppBusiness:
            return "WhatsApp Business"
        }
    }

    var systemImage: String {
        switch self {
        case .whatsApp:
            return "message.fill"
        case .whatsAppBusiness:
            return "briefcase.fill"
        }
    }

    init?(storedValue: String?) {
        guard let storedValue else { return nil }
        let normalized = storedValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }

        switch normalized {
        case "whatsapp", "regularwhatsapp", "personalwhatsapp":
            self = .whatsApp
        case "whatsappbusiness", "businesswhatsapp":
            self = .whatsAppBusiness
        default:
            return nil
        }
    }
}

private final class ArchiveLibraryStore {
    private let defaultsKey = "SavedArchives.v1"
    private let defaults: UserDefaults
    private(set) var didTrimArchivesDuringLastLoad = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [SavedArchive] {
        didTrimArchivesDuringLastLoad = false
        guard let data = defaults.data(forKey: defaultsKey) else { return [] }
        guard let decodedArchives = try? JSONDecoder().decode([SavedArchive].self, from: data) else {
            return []
        }
        let migratedArchives = Self.migratedArchives(from: decodedArchives)
        didTrimArchivesDuringLastLoad = migratedArchives.count < decodedArchives.count
        if migratedArchives != decodedArchives {
            save(migratedArchives)
        }
        return migratedArchives
    }

    func save(_ archives: [SavedArchive]) {
        guard let data = try? JSONEncoder().encode(archives) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    private static func migratedArchives(from archives: [SavedArchive]) -> [SavedArchive] {
        var migratedArchives: [SavedArchive] = []
        var usedKinds = Set<ArchiveKind>()

        for archive in archives {
            let existingKind = archive.kind
            guard let kind = existingKind ?? ArchiveKind.allCases.first(where: { !usedKinds.contains($0) }),
                  !usedKinds.contains(kind),
                  migratedArchives.count < ArchiveKind.allCases.count
            else {
                continue
            }

            var migratedArchive = archive
            migratedArchive.kind = kind
            if existingKind == nil || shouldUseDefaultDisplayName(migratedArchive.displayName) {
                migratedArchive.displayName = kind.defaultDisplayName
            }

            migratedArchives.append(migratedArchive)
            usedKinds.insert(kind)
        }

        return migratedArchives
    }

    private static func shouldUseDefaultDisplayName(_ displayName: String) -> Bool {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return true }
        let lowercasedName = trimmedName.lowercased()

        if trimmedName.count > 34 {
            return true
        }

        return lowercasedName.contains("appdomaingroup")
            || lowercasedName.contains("group.net.whatsapp")
            || lowercasedName.contains("whatsapp.shared")
            || lowercasedName.contains("chatstorage.sqlite")
    }
}

private final class ArchiveAccess {
    let savedArchiveID: UUID
    let archiveRootURL: URL
    let databaseURL: URL

    private let securityScopedURL: URL
    private let didStartSecurityScope: Bool

    convenience init(savedArchive: SavedArchive) throws {
        var isStale = false
        let resolvedURL: URL
        do {
            resolvedURL = try URL(
                resolvingBookmarkData: savedArchive.bookmarkData,
                options: Self.bookmarkResolutionOptions,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            throw ArchiveImportError.bookmarkResolutionFailed(savedArchive.displayName)
        }

        if isStale {
            throw ArchiveImportError.staleBookmark(savedArchive.displayName)
        }

        try self.init(
            savedArchiveID: savedArchive.id,
            selectedURL: resolvedURL,
            selectedResourceIsDirectory: savedArchive.selectedResourceIsDirectory
        )
    }

    init(savedArchiveID: UUID, selectedURL: URL, selectedResourceIsDirectory: Bool) throws {
        self.savedArchiveID = savedArchiveID
        self.securityScopedURL = selectedURL
        self.didStartSecurityScope = selectedURL.startAccessingSecurityScopedResource()

        if selectedResourceIsDirectory {
            self.archiveRootURL = selectedURL.standardizedFileURL
            self.databaseURL = selectedURL
                .appendingPathComponent("ChatStorage.sqlite")
                .standardizedFileURL
        } else {
            self.archiveRootURL = selectedURL.deletingLastPathComponent().standardizedFileURL
            self.databaseURL = selectedURL.standardizedFileURL
        }

        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            if didStartSecurityScope {
                selectedURL.stopAccessingSecurityScopedResource()
            }
            throw ArchiveImportError.missingDatabase(databaseURL)
        }
    }

    deinit {
        if didStartSecurityScope {
            securityScopedURL.stopAccessingSecurityScopedResource()
        }
    }

    private static var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        #if os(macOS)
        return [.withSecurityScope]
        #else
        return []
        #endif
    }
}

@main
struct WhatsAppArchiveApp: App {
    @StateObject private var archiveStore = ArchiveStore()

    var body: some Scene {
        WindowGroup {
            ChatListView()
                .environmentObject(archiveStore)
        }
    }
}

private actor ProfilePhotoService {
    private let resolver: ProfilePhotoResolver

    init(archiveRootURL: URL) {
        resolver = ProfilePhotoResolver(archiveRootURL: archiveRootURL)
    }

    func profilePhotoURL(for chat: ChatSummary) -> URL? {
        resolver.profilePhotoURL(
            contactJID: chat.contactJID,
            contactIdentifier: chat.contactIdentifier,
            additionalIdentifiers: chat.profilePhotoIdentifiers
        )
    }
}

private struct ProfileAvatarCacheKey: Hashable {
    let archiveID: UUID
    let chatID: Int64
    let contactJID: String?
    let contactIdentifier: String?
    let additionalIdentifiers: [String]
}

private struct ProfileAvatarCacheEntry {
    let image: CGImage?
}

private actor ProfileAvatarCache {
    private var entries: [ProfileAvatarCacheKey: ProfileAvatarCacheEntry] = [:]

    func cachedImage(for key: ProfileAvatarCacheKey) -> ProfileAvatarCacheEntry? {
        entries[key]
    }

    func store(_ image: CGImage?, for key: ProfileAvatarCacheKey) {
        if entries.count > 512 {
            entries.removeAll(keepingCapacity: true)
        }
        entries[key] = ProfileAvatarCacheEntry(image: image)
    }
}

@MainActor
final class ArchiveStore: ObservableObject {
    @Published var savedArchives: [SavedArchive]
    @Published var archivesNeedingRelink = Set<UUID>()
    @Published var openingArchiveID: UUID?
    @Published var chats: [ChatSummary] = []
    @Published var selectedChat: ChatSummary?
    @Published var messages: [MessageRow] = []
    @Published var errorMessage: String?
    @Published var olderMessagesErrorMessage: String?
    @Published var isLoadingOlder = false
    @Published var hasMoreOlderMessages = false
    @Published var initialMessageLoadGeneration = 0
    @Published var archiveName = "No Archive"
    @Published var wallpaperURL: URL?
    @Published var wallpaperTheme: ChatWallpaperTheme {
        didSet {
            defaults.set(wallpaperTheme.rawValue, forKey: Self.wallpaperThemeDefaultsKey)
        }
    }
    @Published var currentArchiveID: UUID?

    let contactNameResolver = ContactNameResolver()

    var isArchiveOpen: Bool {
        database != nil
    }

    var isOpeningArchive: Bool {
        openingArchiveID != nil
    }

    let messageLimit = 500
    private var messageFetchLimit: Int {
        messageLimit + 1
    }

    private let libraryStore = ArchiveLibraryStore()
    private let defaults: UserDefaults
    private var database: WhatsAppDatabase?
    private var archiveAccess: ArchiveAccess?
    private var profilePhotoService: ProfilePhotoService?
    private let profileAvatarCache = ProfileAvatarCache()
    private var baseChats: [ChatSummary] = []
    private var baseMessages: [MessageRow] = []
    private var contactNameResolverCancellable: AnyCancellable?

    private static let wallpaperThemeDefaultsKey = "ChatWallpaperTheme.v2"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        wallpaperTheme = ChatWallpaperTheme(rawValue: defaults.string(forKey: Self.wallpaperThemeDefaultsKey) ?? "")
            ?? .archiveDefault
        let loadedArchives = libraryStore.load().sorted(by: Self.archiveSort)
        savedArchives = loadedArchives
        contactNameResolverCancellable = contactNameResolver.$changeToken.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshContactEnrichment()
            }
        }
        if libraryStore.didTrimArchivesDuringLastLoad {
            errorMessage = "Only the WhatsApp and WhatsApp Business slots are kept. Extra saved archive records were removed from this app, but archive files were not deleted."
        }
    }

    func loadDefaultArchiveIfAvailable() {
        // Archive selection is now explicit through the saved archive library.
    }

    func savedArchive(for kind: ArchiveKind) -> SavedArchive? {
        savedArchives.first { $0.kind == kind }
    }

    func openPickedURL(_ url: URL, kind: ArchiveKind) {
        guard openingArchiveID == nil else { return }
        guard savedArchive(for: kind) == nil else {
            errorMessage = "\(kind.defaultDisplayName) is already added. Remove it or relink the existing slot."
            return
        }
        guard savedArchives.count < ArchiveKind.allCases.count else {
            errorMessage = "Both archive slots are already filled."
            return
        }

        let openingID = UUID()
        openingArchiveID = openingID
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.openPickedURLImmediately(url, kind: kind, openingID: openingID)
        }
    }

    func openSavedArchive(_ archive: SavedArchive) {
        guard openingArchiveID == nil else { return }
        openingArchiveID = archive.id
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.openSavedArchiveImmediately(archive)
        }
    }

    func openDemoArchive() {
        guard openingArchiveID == nil else { return }
        openingArchiveID = Self.demoArchiveID
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.openDemoArchiveImmediately()
        }
    }

    func relinkArchive(id: UUID, with url: URL) {
        guard openingArchiveID == nil else { return }
        openingArchiveID = id
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.relinkArchiveImmediately(id: id, with: url)
        }
    }

    private func openPickedURLImmediately(_ url: URL, kind: ArchiveKind, openingID: UUID) {
        defer {
            if openingArchiveID == openingID {
                openingArchiveID = nil
            }
        }

        let didStartSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if didStartSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let selectedResourceIsDirectory = try isDirectory(url)
            let databaseURL = try databaseURL(in: url)
            guard FileManager.default.fileExists(atPath: databaseURL.path) else {
                throw ArchiveImportError.missingDatabase(databaseURL)
            }

            var savedArchive = SavedArchive(
                id: UUID(),
                displayName: kind.defaultDisplayName,
                archiveKind: kind.rawValue,
                bookmarkData: try Self.bookmarkData(for: url),
                selectedResourceIsDirectory: selectedResourceIsDirectory,
                createdAt: Date(),
                lastOpenedAt: nil,
                chatCount: nil
            )

            let access = try ArchiveAccess(
                savedArchiveID: savedArchive.id,
                selectedURL: url,
                selectedResourceIsDirectory: selectedResourceIsDirectory
            )
            openArchive(savedArchive: &savedArchive, access: access, shouldSave: true)
        } catch {
            closeArchive()
            errorMessage = error.localizedDescription
        }
    }

    private func openSavedArchiveImmediately(_ archive: SavedArchive) {
        defer {
            if openingArchiveID == archive.id {
                openingArchiveID = nil
            }
        }

        do {
            var savedArchive = archive
            let access = try ArchiveAccess(savedArchive: archive)
            openArchive(savedArchive: &savedArchive, access: access, shouldSave: true)
            archivesNeedingRelink.remove(archive.id)
        } catch ArchiveImportError.staleBookmark {
            archivesNeedingRelink.insert(archive.id)
            errorMessage = ArchiveImportError.staleBookmark(archive.displayName).localizedDescription
        } catch ArchiveImportError.bookmarkResolutionFailed {
            archivesNeedingRelink.insert(archive.id)
            errorMessage = ArchiveImportError.bookmarkResolutionFailed(archive.displayName).localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openDemoArchiveImmediately() {
        defer {
            if openingArchiveID == Self.demoArchiveID {
                openingArchiveID = nil
            }
        }

        do {
            let demoArchiveURL = try Self.bundledDemoArchiveURL()
            var demoArchive = SavedArchive(
                id: Self.demoArchiveID,
                displayName: "Demo Archive",
                archiveKind: nil,
                bookmarkData: Data(),
                selectedResourceIsDirectory: true,
                createdAt: Date(),
                lastOpenedAt: nil,
                chatCount: nil
            )
            let access = try ArchiveAccess(
                savedArchiveID: demoArchive.id,
                selectedURL: demoArchiveURL,
                selectedResourceIsDirectory: true
            )
            openArchive(savedArchive: &demoArchive, access: access, shouldSave: false)
        } catch {
            closeArchive()
            errorMessage = error.localizedDescription
        }
    }

    private func relinkArchiveImmediately(id: UUID, with url: URL) {
        defer {
            if openingArchiveID == id {
                openingArchiveID = nil
            }
        }

        guard let index = savedArchives.firstIndex(where: { $0.id == id }) else { return }
        let didStartSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if didStartSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let selectedResourceIsDirectory = try isDirectory(url)
            let databaseURL = try databaseURL(in: url)
            guard FileManager.default.fileExists(atPath: databaseURL.path) else {
                throw ArchiveImportError.missingDatabase(databaseURL)
            }

            var savedArchive = savedArchives[index]
            savedArchive.bookmarkData = try Self.bookmarkData(for: url)
            savedArchive.selectedResourceIsDirectory = selectedResourceIsDirectory
            if savedArchive.kind == nil {
                let fallbackKind = availableKind(excluding: savedArchive.id) ?? .whatsApp
                savedArchive.kind = fallbackKind
                savedArchive.displayName = fallbackKind.defaultDisplayName
            }

            let access = try ArchiveAccess(
                savedArchiveID: savedArchive.id,
                selectedURL: url,
                selectedResourceIsDirectory: selectedResourceIsDirectory
            )
            openArchive(savedArchive: &savedArchive, access: access, shouldSave: true)
            archivesNeedingRelink.remove(id)
        } catch {
            archivesNeedingRelink.insert(id)
            errorMessage = error.localizedDescription
        }
    }

    func renameArchive(_ archive: SavedArchive, to displayName: String) {
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDisplayName.isEmpty else {
            errorMessage = "Enter a label for this archive."
            return
        }
        guard let index = savedArchives.firstIndex(where: { $0.id == archive.id }) else { return }

        savedArchives[index].displayName = trimmedDisplayName
        if currentArchiveID == archive.id {
            archiveName = trimmedDisplayName
        }
        libraryStore.save(savedArchives)
    }

    func removeArchive(_ archive: SavedArchive) {
        if currentArchiveID == archive.id {
            closeArchive()
        }
        savedArchives.removeAll { $0.id == archive.id }
        archivesNeedingRelink.remove(archive.id)
        libraryStore.save(savedArchives)
    }

    func closeArchive() {
        database = nil
        archiveAccess = nil
        profilePhotoService = nil
        currentArchiveID = nil
        baseChats = []
        baseMessages = []
        openingArchiveID = nil
        chats = []
        selectedChat = nil
        messages = []
        resetPaginationState()
        archiveName = "No Archive"
        wallpaperURL = nil
    }

    func loadMessages(for chat: ChatSummary) {
        guard let database else { return }
        do {
            let loadedMessages = try database.fetchMessages(
                sessionIDs: chat.sessionIDs,
                limit: messageFetchLimit,
                includeStatusStoryMessages: chat.classification == .statusStoryFragment
            )
            hasMoreOlderMessages = loadedMessages.count > messageLimit
            baseMessages = hasMoreOlderMessages ? Array(loadedMessages.dropFirst()) : loadedMessages
            messages = enrichedMessages(baseMessages)
            olderMessagesErrorMessage = nil
            isLoadingOlder = false
            initialMessageLoadGeneration += 1
            errorMessage = nil
        } catch {
            messages = []
            resetPaginationState()
            errorMessage = error.localizedDescription
        }
    }

    func loadOlderMessages() {
        guard let database, let chat = selectedChat, !isLoadingOlder, hasMoreOlderMessages else { return }
        guard let cursor = messages.first?.paginationCursor else {
            hasMoreOlderMessages = false
            olderMessagesErrorMessage = "Cannot load older messages because the oldest loaded message has no date."
            return
        }

        isLoadingOlder = true
        let chatID = chat.id
        let sessionIDs = chat.sessionIDs

        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            defer { self.isLoadingOlder = false }

            do {
                let olderMessages = try database.fetchOlderMessages(
                    sessionIDs: sessionIDs,
                    before: cursor,
                    limit: self.messageFetchLimit,
                    includeStatusStoryMessages: chat.classification == .statusStoryFragment
                )
                guard self.selectedChat?.id == chatID else { return }
                self.hasMoreOlderMessages = olderMessages.count > self.messageLimit
                let visibleOlderMessages = self.hasMoreOlderMessages ? Array(olderMessages.dropFirst()) : olderMessages
                self.baseMessages.insert(contentsOf: visibleOlderMessages, at: 0)
                self.messages = self.enrichedMessages(self.baseMessages)
                self.olderMessagesErrorMessage = nil
                self.errorMessage = nil
            } catch {
                guard self.selectedChat?.id == chatID else { return }
                self.olderMessagesErrorMessage = "Could not load older messages: \(error.localizedDescription)"
            }
        }
    }

    func mediaItems(for chat: ChatSummary, filter: ChatMediaFilter) throws -> [ChatMediaItem] {
        try mediaLibraryPage(for: chat, filter: filter).items
    }

    func mediaLibraryPage(for chat: ChatSummary, filter: ChatMediaFilter) throws -> ChatMediaLibraryPage {
        guard let database else {
            return ChatMediaLibraryPage(
                items: [],
                summary: ChatMediaLoadSummary(
                    totalRowsMatchingFilter: 0,
                    rowsScanned: 0,
                    displayedRows: 0,
                    rowsWithLocalPath: 0,
                    photoRows: 0,
                    videoRows: 0,
                    audioRows: 0,
                    otherRows: 0,
                    resolvedFileURLRows: 0,
                    existingFileRows: 0,
                    readableFileRows: 0,
                    missingOrUnresolvedRows: 0,
                    statusStoryRowsExcluded: 0,
                    queryCapMayHideRows: false
                )
            )
        }
        return try database.fetchChatMediaLibraryPage(
            sessionIDs: chat.sessionIDs,
            filter: filter,
            includeStatusStoriesInAll: chat.classification == .statusStoryFragment
        )
    }

    private func openArchive(savedArchive: inout SavedArchive, access: ArchiveAccess, shouldSave: Bool) {
        do {
            let openedDatabase = try WhatsAppDatabase(
                databaseURL: access.databaseURL,
                archiveRootURL: access.archiveRootURL,
                securityScopedURL: nil
            )
            let loadedChats = try openedDatabase.fetchChats()
            database = openedDatabase
            archiveAccess = access
            profilePhotoService = ProfilePhotoService(archiveRootURL: access.archiveRootURL)
            currentArchiveID = savedArchive.id
            baseChats = loadedChats
            baseMessages = []
            chats = enrichedChats(loadedChats)
            selectedChat = nil
            messages = []
            resetPaginationState()
            archiveName = savedArchive.displayName
            wallpaperURL = Self.wallpaperURL(in: access.archiveRootURL)
            errorMessage = nil

            savedArchive.lastOpenedAt = Date()
            savedArchive.chatCount = loadedChats.count
            if shouldSave {
                upsert(savedArchive)
            }
        } catch {
            database = nil
            archiveAccess = nil
            profilePhotoService = nil
            currentArchiveID = nil
            baseChats = []
            baseMessages = []
            chats = []
            selectedChat = nil
            messages = []
            resetPaginationState()
            archiveName = "No Archive"
            wallpaperURL = nil
            errorMessage = error.localizedDescription
        }
    }

    func profileAvatarImage(for chat: ChatSummary) async -> CGImage? {
        guard let archiveID = currentArchiveID,
              let profilePhotoService,
              chat.classification != .statusStoryFragment else {
            return nil
        }

        let cacheKey = ProfileAvatarCacheKey(
            archiveID: archiveID,
            chatID: chat.id,
            contactJID: chat.contactJID,
            contactIdentifier: chat.contactIdentifier,
            additionalIdentifiers: chat.profilePhotoIdentifiers
        )
        if let cachedResult = await profileAvatarCache.cachedImage(for: cacheKey) {
            return cachedResult.image
        }

        guard let imageURL = await profilePhotoService.profilePhotoURL(for: chat) else {
            await profileAvatarCache.store(nil, for: cacheKey)
            return nil
        }

        let image = await Task.detached(priority: .utility) {
            downsampleAvatarImage(at: imageURL, maxPixelSize: 96)
        }.value
        await profileAvatarCache.store(image, for: cacheKey)
        return image
    }

    private static func wallpaperURL(in archiveRootURL: URL) -> URL? {
        let candidates = [
            "current_wallpaper.jpg",
            "current_wallpaper_dark.jpg"
        ]

        let archiveRootURL = archiveRootURL.standardizedFileURL
        return candidates
            .map { archiveRootURL.appendingPathComponent($0).standardizedFileURL }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func refreshContactEnrichment() {
        chats = enrichedChats(baseChats)
        if let selectedChat,
           let refreshedSelection = chats.first(where: { $0.id == selectedChat.id }) {
            self.selectedChat = refreshedSelection
        }
        messages = enrichedMessages(baseMessages)
    }

    private func enrichedChats(_ chats: [ChatSummary]) -> [ChatSummary] {
        chats.map(enrichedChat)
    }

    private func enrichedChat(_ chat: ChatSummary) -> ChatSummary {
        guard shouldUseDeviceContactName(for: chat),
              let deviceContactName = contactNameResolver.displayName(for: [
                chat.contactJID,
                chat.contactIdentifier
              ]) else {
            return chat
        }

        return ChatSummary(
            id: chat.id,
            sessionIDs: chat.sessionIDs,
            contactJID: chat.contactJID,
            contactIdentifier: chat.contactIdentifier,
            profilePhotoIdentifiers: chat.profilePhotoIdentifiers,
            partnerName: chat.partnerName,
            title: deviceContactName,
            detailText: chat.detailText,
            messageCount: chat.messageCount,
            latestMessageDate: chat.latestMessageDate,
            searchableTitle: deviceContactName,
            classification: chat.classification,
            profilePhotoURL: chat.profilePhotoURL
        )
    }

    private func shouldUseDeviceContactName(for chat: ChatSummary) -> Bool {
        guard !chat.isGroupChat else { return false }
        guard chat.classification == .normalConversation || chat.classification == .separateConversation else {
            return false
        }
        let title = chat.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty
            || title == "Unknown chat"
            || title == "Chat"
            || DisplayNameSanitizer.isRawIdentifierLike(title)
    }

    private func enrichedMessages(_ messages: [MessageRow]) -> [MessageRow] {
        messages.map { message in
            let deviceContactsDisplayName = contactNameResolver.displayName(for: [
                message.groupMemberJID,
                message.senderJID
            ])
            return MessageRow(
                id: message.id,
                isFromMe: message.isFromMe,
                senderJID: message.senderJID,
                pushName: message.pushName,
                groupMemberContactName: message.groupMemberContactName,
                groupMemberFirstName: message.groupMemberFirstName,
                groupMemberJID: message.groupMemberJID,
                profilePushName: message.profilePushName,
                contactsDisplayName: message.contactsDisplayName,
                deviceContactsDisplayName: deviceContactsDisplayName,
                text: message.text,
                messageDate: message.messageDate,
                messageType: message.messageType,
                groupEventType: message.groupEventType,
                isStatusStory: message.isStatusStory,
                media: message.media
            )
        }
    }

    private static func bundledDemoArchiveURL() throws -> URL {
        let bundle = Bundle.main
        let directoryCandidates = [
            bundle.url(forResource: "demo-archive", withExtension: nil),
            bundle.url(forResource: "DemoArchive", withExtension: nil)
        ]

        if let directoryURL = directoryCandidates.compactMap({ $0 }).first,
           FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent("ChatStorage.sqlite").path) {
            return directoryURL.standardizedFileURL
        }

        if let databaseURL = bundle.url(forResource: "ChatStorage", withExtension: "sqlite", subdirectory: "demo-archive") {
            return databaseURL.deletingLastPathComponent().standardizedFileURL
        }

        if let databaseURL = bundle.url(forResource: "ChatStorage", withExtension: "sqlite", subdirectory: "DemoArchive") {
            return databaseURL.deletingLastPathComponent().standardizedFileURL
        }

        throw ArchiveImportError.missingDemoArchive
    }

    private func resetPaginationState() {
        olderMessagesErrorMessage = nil
        isLoadingOlder = false
        hasMoreOlderMessages = false
        initialMessageLoadGeneration += 1
    }

    static let demoArchiveID = UUID(uuidString: "2A625145-C65F-43B8-AF6B-74E33AF8D20B")!

    private func databaseURL(in pickedURL: URL) throws -> URL {
        if try isDirectory(pickedURL) {
            return pickedURL.appendingPathComponent("ChatStorage.sqlite")
        }
        return pickedURL
    }

    private func isDirectory(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        return values.isDirectory == true
    }

    private func upsert(_ archive: SavedArchive) {
        if let index = savedArchives.firstIndex(where: { $0.id == archive.id }) {
            savedArchives[index] = archive
        } else {
            savedArchives.append(archive)
        }
        savedArchives.sort(by: Self.archiveSort)
        libraryStore.save(savedArchives)
    }

    private func availableKind(excluding archiveID: UUID) -> ArchiveKind? {
        let usedKinds = Set(savedArchives.compactMap { archive -> ArchiveKind? in
            guard archive.id != archiveID else { return nil }
            return archive.kind
        })
        return ArchiveKind.allCases.first { !usedKinds.contains($0) }
    }

    private static func archiveSort(_ lhs: SavedArchive, _ rhs: SavedArchive) -> Bool {
        switch (lhs.lastOpenedAt, rhs.lastOpenedAt) {
        case let (left?, right?):
            return left > right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return lhs.createdAt > rhs.createdAt
        }
    }

    private static func bookmarkData(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: bookmarkCreationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private static var bookmarkCreationOptions: URL.BookmarkCreationOptions {
        #if os(macOS)
        return [.withSecurityScope]
        #else
        return []
        #endif
    }

}
