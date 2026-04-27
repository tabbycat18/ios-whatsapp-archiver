import SwiftUI
import UniformTypeIdentifiers
import Combine

#if DEBUG
private let appLaunchDebugStart = Date()

enum AppLaunchDebugLog {
    static func mark(_ phase: String) {
        let milliseconds = Int(Date().timeIntervalSince(appLaunchDebugStart) * 1000)
        print("[AppLaunch] \(phase): \(milliseconds) ms")
    }
}
#endif

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

    init() {
        #if DEBUG
        AppLaunchDebugLog.mark("app startup")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ChatListView()
                .environmentObject(archiveStore)
        }
    }
}

private actor ProfilePhotoService {
    private let resolver: ProfilePhotoResolver

    init(archiveRootURL: URL, databaseURL: URL) {
        resolver = ProfilePhotoResolver(archiveRootURL: archiveRootURL, databaseURL: databaseURL)
    }

    func profilePhotoURL(for chat: ChatSummary) -> URL? {
        resolver.profilePhotoURL(
            contactJID: chat.contactJID,
            contactIdentifier: chat.contactIdentifier,
            additionalIdentifiers: chat.profilePhotoIdentifiers
        )
    }

    func profilePhotoURL(
        for senderJID: String?,
        senderIdentifier: String?,
        additionalIdentifiers: [String] = []
    ) -> URL? {
        resolver.profilePhotoURL(
            contactJID: senderJID,
            contactIdentifier: senderIdentifier,
            additionalIdentifiers: additionalIdentifiers
        )
    }
}

private struct ProfileAvatarCacheKey: Hashable {
    let archiveID: UUID
    let contactJID: String?
    let contactIdentifier: String?
    let additionalIdentifiers: [String]
    let fallbackIdentifier: String?

    init(archiveID: UUID, chat: ChatSummary) {
        func cleaned(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }

        let contactJID = cleaned(chat.contactJID)
        let contactIdentifier = cleaned(chat.contactIdentifier)
        let additionalIdentifiers = chat.profilePhotoIdentifiers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
        let hasContactKey = contactJID != nil || contactIdentifier != nil || !additionalIdentifiers.isEmpty

        self.archiveID = archiveID
        self.contactJID = contactJID
        self.contactIdentifier = contactIdentifier
        self.additionalIdentifiers = additionalIdentifiers
        self.fallbackIdentifier = hasContactKey ? nil : String(chat.id)
    }

    init(
        archiveID: UUID,
        senderJID: String?,
        senderIdentifier: String?,
        additionalIdentifiers: [String] = [],
        fallbackIdentifier: String? = nil
    ) {
        func cleaned(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }

        let contactJID = cleaned(senderJID)
        let contactIdentifier = cleaned(senderIdentifier)
        let normalizedAdditionalIdentifiers = additionalIdentifiers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
        let hasContactKey = contactJID != nil || contactIdentifier != nil || !normalizedAdditionalIdentifiers.isEmpty

        self.archiveID = archiveID
        self.contactJID = contactJID
        self.contactIdentifier = contactIdentifier
        self.additionalIdentifiers = normalizedAdditionalIdentifiers
        self.fallbackIdentifier = hasContactKey ? nil : cleaned(fallbackIdentifier)
    }
}

private struct ProfileAvatarCacheEntry {
    let image: CGImage?
}

enum ProfileAvatarLoadPriority {
    case visible

    var taskPriority: TaskPriority {
        .utility
    }
}

private actor ProfileAvatarLoader {
    private var entries: [ProfileAvatarCacheKey: ProfileAvatarCacheEntry] = [:]
    private var inFlightKeys = Set<ProfileAvatarCacheKey>()
    private var activeLoadCount = 0
    #if DEBUG
    private var cacheHitCount = 0
    private var missingHitCount = 0
    private var decodedCount = 0
    private var missingLoadCount = 0
    #endif

    private let maxCachedEntries = 512
    private let maxConcurrentLoads = 2

    func image(
        for key: ProfileAvatarCacheKey,
        chat: ChatSummary,
        service: ProfilePhotoService,
        priority: ProfileAvatarLoadPriority
    ) async -> CGImage? {
        await image(
            for: key,
            senderJID: chat.contactJID,
            senderIdentifier: chat.contactIdentifier,
            additionalIdentifiers: chat.profilePhotoIdentifiers,
            service: service,
            priority: priority
        )
    }

    func image(
        for key: ProfileAvatarCacheKey,
        senderJID: String?,
        senderIdentifier: String?,
        additionalIdentifiers: [String] = [],
        service: ProfilePhotoService,
        priority: ProfileAvatarLoadPriority
    ) async -> CGImage? {
        if let cachedEntry = entries[key] {
            #if DEBUG
            if cachedEntry.image == nil {
                missingHitCount += 1
            } else {
                cacheHitCount += 1
            }
            #endif
            return cachedEntry.image
        }

        if inFlightKeys.contains(key) {
            return await imageFromInFlightLoad(for: key)
        }

        guard !Task.isCancelled else { return nil }
        inFlightKeys.insert(key)
        guard await acquireLoadSlot() else {
            inFlightKeys.remove(key)
            return nil
        }

        let imageURL = await service.profilePhotoURL(
            for: senderJID,
            senderIdentifier: senderIdentifier,
            additionalIdentifiers: additionalIdentifiers
        )
        guard !Task.isCancelled else {
            releaseLoadSlot()
            inFlightKeys.remove(key)
            return nil
        }

        let image: CGImage?
        if let imageURL {
            let taskPriority = priority.taskPriority
            #if DEBUG
            let decodeStart = Date()
            #endif
            image = await Task.detached(priority: taskPriority) {
                downsampleAvatarImage(at: imageURL, maxPixelSize: 96)
            }.value
            #if DEBUG
            let decodeMilliseconds = Date().timeIntervalSince(decodeStart) * 1000
            if decodeMilliseconds > 50 {
                print("[AvatarLoad] slow decode: \(Int(decodeMilliseconds)) ms")
            }
            #endif
        } else {
            image = nil
        }

        releaseLoadSlot()
        inFlightKeys.remove(key)
        store(image, for: key)
        return image
    }

    private func store(_ image: CGImage?, for key: ProfileAvatarCacheKey) {
        if entries.count > maxCachedEntries {
            entries.removeAll(keepingCapacity: true)
        }
        entries[key] = ProfileAvatarCacheEntry(image: image)
        #if DEBUG
        if image == nil {
            missingLoadCount += 1
        } else {
            decodedCount += 1
        }
        let totalLookups = cacheHitCount + missingHitCount + decodedCount + missingLoadCount
        if totalLookups > 0, totalLookups.isMultiple(of: 100) {
            print("[AvatarLoad] cache hits=\(cacheHitCount) missingHits=\(missingHitCount) decoded=\(decodedCount) missing=\(missingLoadCount)")
        }
        #endif
    }

    private func imageFromInFlightLoad(for key: ProfileAvatarCacheKey) async -> CGImage? {
        while inFlightKeys.contains(key) {
            if Task.isCancelled {
                return nil
            }
            try? await Task.sleep(for: .milliseconds(40))
            if let cachedEntry = entries[key] {
                return cachedEntry.image
            }
        }
        return entries[key]?.image
    }

    private func acquireLoadSlot() async -> Bool {
        let waitDuration: Duration = .milliseconds(50)
        while activeLoadCount >= maxConcurrentLoads {
            if Task.isCancelled {
                return false
            }
            try? await Task.sleep(for: waitDuration)
        }
        activeLoadCount += 1
        return true
    }

    private func releaseLoadSlot() {
        activeLoadCount = max(activeLoadCount - 1, 0)
    }
}

private struct OpenArchiveSnapshot: @unchecked Sendable {
    let database: WhatsAppDatabase
    let chats: [ChatSummary]
    let wallpaperURL: URL?
    let wallpaperDarkURL: URL?
    let openedAt: Date
}

#if DEBUG
private struct ArchiveOpenDebugTimer {
    private let start = Date()
    private var last = Date()

    mutating func mark(_ phase: String) {
        let now = Date()
        let phaseMilliseconds = now.timeIntervalSince(last) * 1000
        let totalMilliseconds = now.timeIntervalSince(start) * 1000
        print("[ArchiveOpen] \(phase): \(Int(phaseMilliseconds)) ms (total \(Int(totalMilliseconds)) ms)")
        last = now
    }

    static func milliseconds(since date: Date) -> Int {
        Int(Date().timeIntervalSince(date) * 1000)
    }
}
#endif

private enum ArchiveOpenMode {
    case manual
    case startupRestore
}

@MainActor
final class ArchiveStore: ObservableObject {
    @Published var savedArchives: [SavedArchive]
    @Published var archivesNeedingRelink = Set<UUID>()
    @Published var openingArchiveID: UUID?
    @Published private var openingMode: ArchiveOpenMode = .manual
    @Published private(set) var openingArchiveName: String?
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
    @Published var wallpaperDarkURL: URL?
    @Published private(set) var profileAvatarLoadingEnabled = false
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

    var isStartupOpening: Bool {
        isOpeningArchive && openingMode == .startupRestore
    }

    let messageLimit = 250
    private var messageFetchLimit: Int {
        messageLimit + 1
    }

    private let libraryStore = ArchiveLibraryStore()
    private let defaults: UserDefaults
    private var database: WhatsAppDatabase?
    private var archiveAccess: ArchiveAccess?
    private var profilePhotoService: ProfilePhotoService?
    private let profileAvatarLoader = ProfileAvatarLoader()
    private var baseChats: [ChatSummary] = []
    private var baseMessages: [MessageRow] = []
    private var messageLoadRequestID: UUID?
    private var contactNameResolverCancellable: AnyCancellable?
    private var didAttemptStartupRestore = false

    private static let wallpaperThemeDefaultsKey = "ChatWallpaperTheme.v2"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if DEBUG
        AppLaunchDebugLog.mark("ArchiveStore init started")
        #endif
        wallpaperTheme = ChatWallpaperTheme(rawValue: defaults.string(forKey: Self.wallpaperThemeDefaultsKey) ?? "")
            ?? .archiveDefault
        #if DEBUG
        let savedMetadataStart = Date()
        #endif
        let loadedArchives = libraryStore.load().sorted(by: Self.archiveSort)
        savedArchives = loadedArchives
        #if DEBUG
        print("[ArchiveOpen] loading saved archive metadata: \(ArchiveOpenDebugTimer.milliseconds(since: savedMetadataStart)) ms count=\(loadedArchives.count)")
        AppLaunchDebugLog.mark("saved archive metadata loaded")
        #endif
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
        #if DEBUG
        AppLaunchDebugLog.mark("loading startup restore")
        #endif

        guard !didAttemptStartupRestore else { return }
        didAttemptStartupRestore = true
        guard openingArchiveID == nil else { return }
        guard let archive = savedArchives.first(where: { $0.lastOpenedAt != nil }) else {
            #if DEBUG
            print("[ArchiveOpen] startup restore skipped: no recently opened archive")
            #endif
            return
        }

        openingArchiveID = archive.id
        openingArchiveName = archive.displayName
        openingMode = .startupRestore
        #if DEBUG
        print("[ArchiveOpen] startup restore candidate count=1")
        #endif

        Task { @MainActor [weak self] in
            guard let self else { return }
            await Task.yield()
            await self.openSavedArchiveImmediately(archive)
        }
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
        openingMode = .manual
        openingArchiveName = kind.defaultDisplayName
        Task { @MainActor [weak self] in
            await Task.yield()
            await self?.openPickedURLImmediately(url, kind: kind, openingID: openingID)
        }
    }

    func openSavedArchive(_ archive: SavedArchive) {
        guard openingArchiveID == nil else { return }
        openingArchiveID = archive.id
        openingMode = .manual
        openingArchiveName = archive.displayName
        Task { @MainActor [weak self] in
            await Task.yield()
            await self?.openSavedArchiveImmediately(archive)
        }
    }

    func openDemoArchive() {
        guard openingArchiveID == nil else { return }
        openingArchiveID = Self.demoArchiveID
        openingMode = .manual
        openingArchiveName = "Demo Archive"
        Task { @MainActor [weak self] in
            await Task.yield()
            await self?.openDemoArchiveImmediately()
        }
    }

    func relinkArchive(id: UUID, with url: URL) {
        guard openingArchiveID == nil else { return }
        openingArchiveID = id
        openingMode = .manual
        if let archive = savedArchives.first(where: { $0.id == id }) {
            openingArchiveName = archive.displayName
        }
        Task { @MainActor [weak self] in
            await Task.yield()
            await self?.relinkArchiveImmediately(id: id, with: url)
        }
    }

    private func openPickedURLImmediately(_ url: URL, kind: ArchiveKind, openingID: UUID) async {
        defer {
            if openingArchiveID == openingID {
                openingArchiveID = nil
                openingMode = .manual
                openingArchiveName = nil
            }
        }

        #if DEBUG
        let bookmarkStart = Date()
        #endif
        let didStartSecurityScope = url.startAccessingSecurityScopedResource()
        #if DEBUG
        print("[ArchiveOpen] resolving security-scoped bookmark: \(ArchiveOpenDebugTimer.milliseconds(since: bookmarkStart)) ms source=picker access=\(didStartSecurityScope)")
        #endif
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
            try await openArchive(savedArchive: &savedArchive, access: access, shouldSave: true)
        } catch {
            closeArchive()
            errorMessage = error.localizedDescription
        }
    }

    private func openSavedArchiveImmediately(_ archive: SavedArchive) async {
        defer {
            if openingArchiveID == archive.id {
                openingArchiveID = nil
                openingMode = .manual
                openingArchiveName = nil
            }
        }

        do {
            var savedArchive = archive
            #if DEBUG
            let bookmarkStart = Date()
            #endif
            let access = try ArchiveAccess(savedArchive: archive)
            #if DEBUG
            print("[ArchiveOpen] resolving security-scoped bookmark: \(ArchiveOpenDebugTimer.milliseconds(since: bookmarkStart)) ms source=saved")
            #endif
            try await openArchive(savedArchive: &savedArchive, access: access, shouldSave: true)
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

    private func openDemoArchiveImmediately() async {
        defer {
            if openingArchiveID == Self.demoArchiveID {
                openingArchiveID = nil
                openingMode = .manual
                openingArchiveName = nil
            }
        }

        do {
            #if DEBUG
            var timer = ArchiveOpenDebugTimer()
            #endif
            let demoArchiveURL = try Self.bundledDemoArchiveURL()
            #if DEBUG
            timer.mark("demo archive preparation")
            #endif
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
            try await openArchive(savedArchive: &demoArchive, access: access, shouldSave: false)
        } catch {
            closeArchive()
            errorMessage = error.localizedDescription
        }
    }

    private func relinkArchiveImmediately(id: UUID, with url: URL) async {
        defer {
            if openingArchiveID == id {
                openingArchiveID = nil
                openingMode = .manual
                openingArchiveName = nil
            }
        }

        guard let index = savedArchives.firstIndex(where: { $0.id == id }) else { return }
        #if DEBUG
        let bookmarkStart = Date()
        #endif
        let didStartSecurityScope = url.startAccessingSecurityScopedResource()
        #if DEBUG
        print("[ArchiveOpen] resolving security-scoped bookmark: \(ArchiveOpenDebugTimer.milliseconds(since: bookmarkStart)) ms source=relink access=\(didStartSecurityScope)")
        #endif
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
            try await openArchive(savedArchive: &savedArchive, access: access, shouldSave: true)
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
        openingMode = .manual
        openingArchiveName = nil
        database = nil
        archiveAccess = nil
        profilePhotoService = nil
        currentArchiveID = nil
        profileAvatarLoadingEnabled = false
        baseChats = []
        baseMessages = []
        messageLoadRequestID = nil
        openingArchiveID = nil
        chats = []
        selectedChat = nil
        messages = []
        resetPaginationState()
        archiveName = "No Archive"
        wallpaperURL = nil
        wallpaperDarkURL = nil
    }

    func loadMessages(for chat: ChatSummary) {
        guard let database else { return }
        let requestID = UUID()
        messageLoadRequestID = requestID
        let chatID = chat.id
        let sessionIDs = chat.sessionIDs
        let includeStatusStoryMessages = chat.classification == .statusStoryFragment
        let fetchLimit = messageFetchLimit
        let visibleLimit = messageLimit

        baseMessages = []
        messages = []
        olderMessagesErrorMessage = nil
        isLoadingOlder = false
        hasMoreOlderMessages = false

        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }

            do {
                let loadedMessages = try await Self.fetchMessages(
                    database: database,
                    sessionIDs: sessionIDs,
                    limit: fetchLimit,
                    includeStatusStoryMessages: includeStatusStoryMessages
                )
                guard self.messageLoadRequestID == requestID,
                      self.selectedChat?.id == chatID else {
                    return
                }

                self.hasMoreOlderMessages = loadedMessages.count > visibleLimit
                self.baseMessages = self.hasMoreOlderMessages ? Array(loadedMessages.dropFirst()) : loadedMessages
                self.messages = self.enrichedMessages(self.baseMessages)
                self.olderMessagesErrorMessage = nil
                self.isLoadingOlder = false
                self.initialMessageLoadGeneration += 1
                self.errorMessage = nil
            } catch {
                guard self.messageLoadRequestID == requestID,
                      self.selectedChat?.id == chatID else {
                    return
                }
                self.messages = []
                self.resetPaginationState()
                self.errorMessage = error.localizedDescription
            }
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
        let requestID = messageLoadRequestID
        let chatID = chat.id
        let sessionIDs = chat.sessionIDs
        let fetchLimit = messageFetchLimit
        let visibleLimit = messageLimit
        let includeStatusStoryMessages = chat.classification == .statusStoryFragment

        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            defer { self.isLoadingOlder = false }

            do {
                let olderMessages = try await Self.fetchOlderMessages(
                    database: database,
                    sessionIDs: sessionIDs,
                    before: cursor,
                    limit: fetchLimit,
                    includeStatusStoryMessages: includeStatusStoryMessages
                )
                guard self.messageLoadRequestID == requestID,
                      self.selectedChat?.id == chatID else {
                    return
                }
                self.hasMoreOlderMessages = olderMessages.count > visibleLimit
                let visibleOlderMessages = self.hasMoreOlderMessages ? Array(olderMessages.dropFirst()) : olderMessages
                self.baseMessages.insert(contentsOf: visibleOlderMessages, at: 0)
                self.messages = self.enrichedMessages(self.baseMessages)
                self.olderMessagesErrorMessage = nil
                self.errorMessage = nil
            } catch {
                guard self.messageLoadRequestID == requestID,
                      self.selectedChat?.id == chatID else {
                    return
                }
                self.olderMessagesErrorMessage = "Could not load older messages: \(error.localizedDescription)"
            }
        }
    }

    func mediaItems(for chat: ChatSummary, filter: ChatMediaFilter) throws -> [ChatMediaItem] {
        try mediaLibraryPage(for: chat, filter: filter).items
    }

    func mediaLibraryPage(for chat: ChatSummary, filter: ChatMediaFilter, limit: Int = 300) throws -> ChatMediaLibraryPage {
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
            includeStatusStoriesInAll: chat.classification == .statusStoryFragment,
            limit: limit
        )
    }

    private func openArchive(savedArchive: inout SavedArchive, access: ArchiveAccess, shouldSave: Bool) async throws {
        do {
            #if DEBUG
            var openTimer = ArchiveOpenDebugTimer()
            openTimer.mark("open flow start")
            #endif
            let snapshot = try await Self.loadArchiveSnapshot(
                databaseURL: access.databaseURL,
                archiveRootURL: access.archiveRootURL
            )
            guard openingArchiveID != nil else { return }
            #if DEBUG
            openTimer.mark("fetch snapshot complete chats=\(snapshot.chats.count)")
            #endif

            #if DEBUG
            let avatarSetupStart = Date()
            #endif
            database = snapshot.database
            archiveAccess = access
            profilePhotoService = ProfilePhotoService(archiveRootURL: access.archiveRootURL, databaseURL: access.databaseURL)
            currentArchiveID = savedArchive.id
            profileAvatarLoadingEnabled = false
            enableProfileAvatarLoading(after: .milliseconds(2_000), archiveID: savedArchive.id)
            #if DEBUG
            print("[ArchiveOpen] avatar/profile setup: \(ArchiveOpenDebugTimer.milliseconds(since: avatarSetupStart)) ms deferred=1")
            openTimer.mark("avatar/profile setup")
            #endif
            baseChats = snapshot.chats
            baseMessages = []
            messageLoadRequestID = nil
            chats = enrichedChats(snapshot.chats)
            #if DEBUG
            print("[ArchiveOpen] first chat list render handoff: \(ArchiveOpenDebugTimer.milliseconds(since: snapshot.openedAt)) ms chats=\(snapshot.chats.count)")
            openTimer.mark("chat list ready")
            #endif
            selectedChat = nil
            messages = []
            resetPaginationState()
            archiveName = savedArchive.displayName
            wallpaperURL = snapshot.wallpaperURL
            wallpaperDarkURL = snapshot.wallpaperDarkURL
            errorMessage = nil
            contactNameResolver.loadContactsIfEnabled()

            savedArchive.lastOpenedAt = Date()
            savedArchive.chatCount = snapshot.chats.count
            if shouldSave {
                upsert(savedArchive)
            }
            #if DEBUG
            print("[ArchiveOpen] open flow complete: chats=\(snapshot.chats.count)")
            #endif
        } catch {
            database = nil
            archiveAccess = nil
            profilePhotoService = nil
            currentArchiveID = nil
            profileAvatarLoadingEnabled = false
            baseChats = []
            baseMessages = []
            messageLoadRequestID = nil
            chats = []
            selectedChat = nil
            messages = []
            resetPaginationState()
            archiveName = "No Archive"
            wallpaperURL = nil
            wallpaperDarkURL = nil
            throw error
        }
    }

    nonisolated private static func loadArchiveSnapshot(databaseURL: URL, archiveRootURL: URL) async throws -> OpenArchiveSnapshot {
        let openedAt = Date()
        return try await Task.detached(priority: .userInitiated) {
            #if DEBUG
            var timer = ArchiveOpenDebugTimer()
            #endif

            let openedDatabase = try WhatsAppDatabase(
                databaseURL: databaseURL,
                archiveRootURL: archiveRootURL,
                securityScopedURL: nil
            )
            #if DEBUG
            timer.mark("opening ChatStorage.sqlite complete")
            #endif

            let loadedChats = try openedDatabase.fetchChats()
            #if DEBUG
            timer.mark("fetchChats returned count=\(loadedChats.count)")
            #endif

            let lightWallpaperURL = Self.wallpaperURL(in: archiveRootURL, filename: "current_wallpaper.jpg")
                ?? Self.wallpaperURL(in: archiveRootURL, filename: "current_wallpaper_dark.jpg")
            let darkWallpaperURL = Self.wallpaperURL(in: archiveRootURL, filename: "current_wallpaper_dark.jpg")
                ?? lightWallpaperURL
            #if DEBUG
            timer.mark("wallpaper setup")
            #endif

            return OpenArchiveSnapshot(
                database: openedDatabase,
                chats: loadedChats,
                wallpaperURL: lightWallpaperURL,
                wallpaperDarkURL: darkWallpaperURL,
                openedAt: openedAt
            )
        }.value
    }

    nonisolated private static func fetchMessages(
        database: WhatsAppDatabase,
        sessionIDs: [Int64],
        limit: Int,
        includeStatusStoryMessages: Bool
    ) async throws -> [MessageRow] {
        try await Task.detached(priority: .userInitiated) {
            try database.fetchMessages(
                sessionIDs: sessionIDs,
                limit: limit,
                includeStatusStoryMessages: includeStatusStoryMessages
            )
        }.value
    }

    nonisolated private static func fetchOlderMessages(
        database: WhatsAppDatabase,
        sessionIDs: [Int64],
        before cursor: MessagePaginationCursor,
        limit: Int,
        includeStatusStoryMessages: Bool
    ) async throws -> [MessageRow] {
        try await Task.detached(priority: .utility) {
            try database.fetchOlderMessages(
                sessionIDs: sessionIDs,
                before: cursor,
                limit: limit,
                includeStatusStoryMessages: includeStatusStoryMessages
            )
        }.value
    }

    func profileAvatarImage(for chat: ChatSummary, priority: ProfileAvatarLoadPriority) async -> CGImage? {
        guard profileAvatarLoadingEnabled,
              let archiveID = currentArchiveID,
              let profilePhotoService,
              chat.classification != .statusStoryFragment else {
            return nil
        }

        return await profileAvatarLoader.image(
            for: ProfileAvatarCacheKey(archiveID: archiveID, chat: chat),
            chat: chat,
            service: profilePhotoService,
            priority: priority
        )
    }

    func profileAvatarImage(
        forSenderJID senderJID: String?,
        senderIdentifier: String?,
        fallbackIdentifier: String?,
        priority: ProfileAvatarLoadPriority
    ) async -> CGImage? {
        guard profileAvatarLoadingEnabled,
              let archiveID = currentArchiveID,
              let profilePhotoService else {
            return nil
        }

        return await profileAvatarLoader.image(
            for: ProfileAvatarCacheKey(
                archiveID: archiveID,
                senderJID: senderJID,
                senderIdentifier: senderIdentifier,
                fallbackIdentifier: fallbackIdentifier
            ),
            senderJID: senderJID,
            senderIdentifier: senderIdentifier,
            service: profilePhotoService,
            priority: priority
        )
    }

    private func enableProfileAvatarLoading(after delay: Duration, archiveID: UUID) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self,
                  self.currentArchiveID == archiveID,
                  self.database != nil
            else {
                return
            }
            self.profileAvatarLoadingEnabled = true
        }
    }

    nonisolated private static func wallpaperURL(in archiveRootURL: URL, filename: String) -> URL? {
        let archiveRootURL = archiveRootURL.standardizedFileURL
        let url = archiveRootURL.appendingPathComponent(filename).standardizedFileURL
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
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
        if let cachedDemoArchiveURL {
            return cachedDemoArchiveURL
        }

        let bundle = Bundle.main
        let directoryCandidates = [
            bundle.url(forResource: "demo-archive", withExtension: nil),
            bundle.url(forResource: "DemoArchive", withExtension: nil)
        ]

        if let directoryURL = directoryCandidates.compactMap({ $0 }).first,
           FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent("ChatStorage.sqlite").path) {
            let preparedURL = directoryURL.standardizedFileURL
            cachedDemoArchiveURL = preparedURL
            return preparedURL
        }

        if let databaseURL = bundle.url(forResource: "ChatStorage", withExtension: "sqlite", subdirectory: "demo-archive") {
            let preparedURL = databaseURL.deletingLastPathComponent().standardizedFileURL
            cachedDemoArchiveURL = preparedURL
            return preparedURL
        }

        if let databaseURL = bundle.url(forResource: "ChatStorage", withExtension: "sqlite", subdirectory: "DemoArchive") {
            let preparedURL = databaseURL.deletingLastPathComponent().standardizedFileURL
            cachedDemoArchiveURL = preparedURL
            return preparedURL
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
    private static var cachedDemoArchiveURL: URL?

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
