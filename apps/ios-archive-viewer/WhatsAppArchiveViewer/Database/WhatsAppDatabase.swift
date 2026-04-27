import Foundation
import SQLite3
import UniformTypeIdentifiers

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private struct MediaSchema {
    let columns: Set<String>

    var canJoinMessages: Bool {
        columns.contains("ZMESSAGE")
    }

    func select(_ column: String, as alias: String) -> String {
        if columns.contains(column) {
            return "mi.\(column) AS \(alias)"
        }
        return "NULL AS \(alias)"
    }
}

private struct MediaPathResolution {
    let relativePath: String?
    let fileURL: URL?
    let fileName: String?
    let existsInArchive: Bool
    let isReadable: Bool
}

private struct MediaClassificationInput {
    let messageType: Int?
    let groupEventType: Int?
    let localPath: String?
    let title: String?
    let mediaOrigin: Int?
    let mediaURL: String?
    let vCardName: String?
    let vCardString: String?
    let latitude: Double?
    let longitude: Double?
    let durationSeconds: Double?
}

private struct ChatSummaryRow {
    let id: Int64
    let identityKey: String
    let contactJID: String?
    let contactIdentifier: String?
    let profilePhotoIdentifiers: [String]
    let partnerName: String?
    let title: String
    let profilePhotoURL: URL?
    let messageCount: Int
    let totalMessageCount: Int
    let userVisibleMessageCount: Int
    let systemMessageCount: Int
    let statusStoryMessageCount: Int
    let latestUserVisibleMessageDate: Date?
    let latestAnyMessageDate: Date?
    let fallbackMessageDate: Date?
}

private struct RawChatSummaryRow {
    let id: Int64
    let contactJID: String?
    let contactIdentifier: String?
    let partnerName: String?
    let sanitizedLastMessageDate: Date?
    let totalMessageCount: Int
    let userVisibleMessageCount: Int
    let systemMessageCount: Int
    let statusStoryMessageCount: Int
    let latestUserVisibleMessageDate: Date?
    let latestAnyMessageDate: Date?
}

private struct ContactIdentity {
    let key: String
    let displayName: String?
    let profilePhotoIdentifiers: [String]
}

private struct ChatActivityMetrics {
    let messageCount: Int
    let totalMessageCount: Int
    let userVisibleMessageCount: Int
    let systemMessageCount: Int
    let statusStoryMessageCount: Int

    var hasUserVisibleMessages: Bool {
        userVisibleMessageCount > 0
    }

    var hasOnlyStatusStoryMessages: Bool {
        totalMessageCount > 0 && statusStoryMessageCount == totalMessageCount
    }
}

private struct ChatSummaryDraft {
    let id: Int64
    let sessionIDs: [Int64]
    let contactJID: String?
    let contactIdentifier: String?
    let profilePhotoIdentifiers: [String]
    let partnerName: String?
    let title: String
    let profilePhotoURL: URL?
    let detailText: String
    let latestUserVisibleMessageDate: Date?
    let latestAnyMessageDate: Date?
    let fallbackMessageDate: Date?
    let searchableTitle: String
    let activity: ChatActivityMetrics
}

#if DEBUG
private struct FetchChatsDebugTimer {
    private let start = Date()
    private var last = Date()

    mutating func mark(_ phase: String) {
        let now = Date()
        let phaseMilliseconds = now.timeIntervalSince(last) * 1000
        let totalMilliseconds = now.timeIntervalSince(start) * 1000
        print("[ArchiveOpen] \(phase): \(Int(phaseMilliseconds)) ms (fetchChats total \(Int(totalMilliseconds)) ms)")
        last = now
    }

    static func milliseconds(since date: Date) -> Int {
        Int(Date().timeIntervalSince(date) * 1000)
    }
}

private struct DatabaseOpenDebugTimer {
    private let start = Date()
    private var last = Date()

    mutating func mark(_ phase: String) {
        let now = Date()
        let phaseMilliseconds = now.timeIntervalSince(last) * 1000
        let totalMilliseconds = now.timeIntervalSince(start) * 1000
        print("[ArchiveOpen] \(phase): \(Int(phaseMilliseconds)) ms (database open total \(Int(totalMilliseconds)) ms)")
        last = now
    }
}
#endif

final class ProfilePhotoResolver {
    private let archiveRootURL: URL
    private let databaseURL: URL
    private let fileManager: FileManager
    private var resolvedURLsByCacheKey: [String: URL] = [:]
    private var unresolvedCacheKeys = Set<String>()
    private var database: OpaquePointer?
    private var didDiscoverMissingProfilePictureTable = false
    private lazy var existingProfileDirectoryURLs: [URL] = Self.profileDirectories.compactMap { directory in
        let directoryURL = archiveRootURL.appendingPathComponent(directory, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return directoryURL
    }

    init(archiveRootURL: URL, databaseURL: URL? = nil, fileManager: FileManager = .default) {
        self.archiveRootURL = archiveRootURL.standardizedFileURL
        self.databaseURL = (databaseURL ?? archiveRootURL.appendingPathComponent("ChatStorage.sqlite")).standardizedFileURL
        self.fileManager = fileManager
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    func profilePhotoURL(
        contactJID: String?,
        contactIdentifier: String?,
        additionalIdentifiers: [String] = []
    ) -> URL? {
        let lookupIdentifiers = profilePictureLookupIdentifiers(
            contactJID: contactJID,
            contactIdentifier: contactIdentifier,
            additionalIdentifiers: additionalIdentifiers
        )
        let candidateFileNames = candidateFileNames(
            contactJID: contactJID,
            contactIdentifier: contactIdentifier,
            additionalIdentifiers: additionalIdentifiers
        )
        guard !lookupIdentifiers.isEmpty || !candidateFileNames.isEmpty else { return nil }

        let cacheKey = "\(lookupIdentifiers.joined(separator: "|"))|\(candidateFileNames.joined(separator: "|"))"
        if let cachedURL = resolvedURLsByCacheKey[cacheKey] {
            return cachedURL
        }
        if unresolvedCacheKeys.contains(cacheKey) {
            return nil
        }

        let resolvedURL = resolveProfilePhotoURL(
            lookupIdentifiers: lookupIdentifiers,
            candidateFileNames: candidateFileNames
        )
        if let resolvedURL {
            resolvedURLsByCacheKey[cacheKey] = resolvedURL
        } else {
            unresolvedCacheKeys.insert(cacheKey)
        }
        return resolvedURL
    }

    private func resolveProfilePhotoURL(lookupIdentifiers: [String], candidateFileNames: [String]) -> URL? {
        if let profilePictureItemURL = resolveProfilePictureItemURL(lookupIdentifiers: lookupIdentifiers) {
            return profilePictureItemURL
        }

        for directoryURL in existingProfileDirectoryURLs {
            for fileName in candidateFileNames {
                for candidate in directCandidateURLs(directoryURL: directoryURL, fileName: fileName) {
                    if isReadableFile(candidate) {
                        return candidate
                    }
                }
            }
        }
        return nil
    }

    private func resolveProfilePictureItemURL(lookupIdentifiers: [String]) -> URL? {
        guard !lookupIdentifiers.isEmpty,
              let database = profilePictureDatabase(),
              !didDiscoverMissingProfilePictureTable,
              (try? tableExists("ZWAPROFILEPICTUREITEM")) == true,
              let columns = try? columns(in: "ZWAPROFILEPICTUREITEM"),
              columns.contains("ZJID"),
              columns.contains("ZPATH")
        else {
            return nil
        }

        let limitedIdentifiers = Array(lookupIdentifiers.prefix(Self.maxProfilePictureLookupIdentifiers))
        let placeholders = Array(repeating: "?", count: limitedIdentifiers.count).joined(separator: ", ")
        let orderSQL = columns.contains("ZREQUESTDATE")
            ? "ORDER BY ZREQUESTDATE DESC, Z_PK DESC"
            : "ORDER BY Z_PK DESC"
        let sql = """
            SELECT ZPATH
            FROM ZWAPROFILEPICTUREITEM
            WHERE lower(trim(ZJID)) IN (\(placeholders))
                AND ZPATH IS NOT NULL
                AND trim(ZPATH) != ''
            \(orderSQL)
            LIMIT \(Self.maxProfilePictureItemRowsPerLookup)
            """
        guard let statement = try? prepare(sql, database: database) else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        for (index, identifier) in limitedIdentifiers.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), identifier, -1, sqliteTransient)
        }

        var stepResult = sqlite3_step(statement)
        while stepResult == SQLITE_ROW {
            if let storedPath = string(statement, 0) {
                for candidate in profilePictureItemCandidateURLs(storedPath: storedPath) {
                    if isReadableFile(candidate) {
                        return candidate
                    }
                }
            }
            stepResult = sqlite3_step(statement)
        }

        return nil
    }

    private func profilePictureDatabase() -> OpaquePointer? {
        if let database {
            return database
        }
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            return nil
        }

        var connection: OpaquePointer?
        let result = sqlite3_open_v2(databaseURL.path, &connection, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let connection else {
            if let connection {
                sqlite3_close(connection)
            }
            return nil
        }

        database = connection
        do {
            try execute("PRAGMA query_only = ON", database: connection)
        } catch {
            sqlite3_close(connection)
            database = nil
            return nil
        }
        return connection
    }

    private func tableExists(_ table: String) throws -> Bool {
        guard let database = profilePictureDatabase() else { return false }
        let statement = try prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1", database: database)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, table, -1, sqliteTransient)
        let result = sqlite3_step(statement)
        if result == SQLITE_ROW {
            return true
        }
        if result == SQLITE_DONE {
            didDiscoverMissingProfilePictureTable = true
            return false
        }
        throw WhatsAppDatabaseError.queryFailed(lastErrorMessage(database: database))
    }

    private func columns(in table: String) throws -> Set<String> {
        guard let database = profilePictureDatabase() else { return [] }
        let statement = try prepare("PRAGMA table_info(\(table))", database: database)
        defer { sqlite3_finalize(statement) }

        var columns = Set<String>()
        var stepResult = sqlite3_step(statement)
        while stepResult == SQLITE_ROW {
            if let column = string(statement, 1) {
                columns.insert(column)
            }
            stepResult = sqlite3_step(statement)
        }
        guard stepResult == SQLITE_DONE else {
            throw WhatsAppDatabaseError.queryFailed(lastErrorMessage(database: database))
        }
        return columns
    }

    private func execute(_ sql: String, database: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? lastErrorMessage(database: database)
            sqlite3_free(errorMessage)
            throw WhatsAppDatabaseError.queryFailed(message)
        }
    }

    private func prepare(_ sql: String, database: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw WhatsAppDatabaseError.queryFailed(lastErrorMessage(database: database))
        }
        return statement
    }

    private func lastErrorMessage(database: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(database))
    }

    private func string(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: text)
    }

    private func isReadableFile(_ url: URL) -> Bool {
        guard fileManager.fileExists(atPath: url.path),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isReadableKey]),
              values.isRegularFile == true,
              values.isReadable != false
        else {
            return false
        }
        return true
    }

    private func directCandidateURLs(directoryURL: URL, fileName: String) -> [URL] {
        guard !fileName.contains("/") else { return [] }

        var urls = [directoryURL.appendingPathComponent(fileName).standardizedFileURL]
        let existingExtension = (fileName as NSString).pathExtension.lowercased()
        for fileExtension in Self.imageExtensions where existingExtension != fileExtension {
            urls.append(
                directoryURL
                    .appendingPathComponent(fileName)
                    .appendingPathExtension(fileExtension)
                    .standardizedFileURL
            )
        }
        return deduplicatedURLs(urls)
    }

    private func profilePictureItemCandidateURLs(storedPath: String) -> [URL] {
        let normalizedPath = storedPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        guard !normalizedPath.isEmpty else { return [] }

        var relativePaths: [String] = []
        if let knownRelativePath = knownProfileRelativePath(from: normalizedPath) {
            relativePaths.append(knownRelativePath)
        }

        if let basename = normalizedPath.split(separator: "/").last.map(String.init), !basename.isEmpty {
            relativePaths.append("Media/Profile/\(basename)")
        }

        var urls: [URL] = []
        for relativePath in relativePaths {
            urls.append(contentsOf: archiveURLs(relativePath: relativePath))
        }
        return deduplicatedURLs(urls)
    }

    private func knownProfileRelativePath(from path: String) -> String? {
        for directory in Self.profileDirectories {
            if path.compare(directory, options: [.caseInsensitive]) == .orderedSame
                || path.range(of: "\(directory)/", options: [.anchored, .caseInsensitive]) != nil {
                return path
            }
            let marker = "/\(directory)/"
            if let range = path.range(of: marker, options: [.caseInsensitive]) {
                let suffixStart = path.index(range.lowerBound, offsetBy: 1)
                return String(path[suffixStart...])
            }
        }
        return nil
    }

    private func archiveURLs(relativePath: String) -> [URL] {
        guard let baseURL = safeArchiveURL(relativePath: relativePath) else {
            return []
        }

        var urls = [baseURL]
        if baseURL.pathExtension.isEmpty {
            urls.append(contentsOf: Self.imageExtensions.map { baseURL.appendingPathExtension($0) })
        }
        return deduplicatedURLs(urls)
    }

    private func safeArchiveURL(relativePath: String) -> URL? {
        let components = relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else {
            return nil
        }

        var url = archiveRootURL
        for component in components {
            url.appendPathComponent(component)
        }

        let standardizedURL = url.standardizedFileURL
        let rootPath = archiveRootURL.standardizedFileURL.path
        guard standardizedURL.path == rootPath || standardizedURL.path.hasPrefix("\(rootPath)/") else {
            return nil
        }
        return standardizedURL
    }

    private func deduplicatedURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            seen.insert(url.path).inserted
        }
    }

    private func profilePictureLookupIdentifiers(
        contactJID: String?,
        contactIdentifier: String?,
        additionalIdentifiers: [String]
    ) -> [String] {
        let values = [contactJID, contactIdentifier] + additionalIdentifiers.map(Optional.some)
        var identifiers: [String] = []

        for value in values {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            guard !trimmed.isEmpty, !trimmed.contains(";"), !trimmed.contains(",") else { continue }

            identifiers.append(trimmed)
            if let localPart = trimmed.split(separator: "@", maxSplits: 1).first.map(String.init), !localPart.isEmpty {
                identifiers.append(localPart)
                let digits = localPart.filter(\.isNumber)
                if digits.count >= 6 {
                    identifiers.append(String(digits))
                    identifiers.append("\(digits)@s.whatsapp.net")
                }
            } else {
                let digits = trimmed.filter(\.isNumber)
                if digits.count >= 6 {
                    identifiers.append(String(digits))
                    identifiers.append("\(digits)@s.whatsapp.net")
                }
            }
        }

        var seen = Set<String>()
        return identifiers
            .filter { $0.count >= 5 }
            .filter { seen.insert($0).inserted }
            .sorted { $0.count > $1.count }
    }

    private func candidateFileNames(contactJID: String?, contactIdentifier: String?, additionalIdentifiers: [String]) -> [String] {
        var names: [String] = []

        if let jid = contactJID?.trimmingCharacters(in: .whitespacesAndNewlines), !jid.isEmpty {
            names.append(jid)
            names.append(fileSystemSafeToken(jid))
            names.append(normalizedToken(jid))
            let localPart = jid.split(separator: "@", maxSplits: 1).first.map(String.init) ?? jid
            names.append(localPart)
            names.append(fileSystemSafeToken(localPart))
            names.append(normalizedToken(localPart))
            let localDigits = localPart.filter(\.isNumber)
            if localDigits.count >= 7 {
                names.append(String(localDigits))
            }
        }

        if let identifier = contactIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !identifier.isEmpty {
            names.append(identifier)
            names.append(fileSystemSafeToken(identifier))
            names.append(normalizedToken(identifier))
            let identifierDigits = identifier.filter(\.isNumber)
            if identifierDigits.count >= 7 {
                names.append(String(identifierDigits))
            }
        }

        for additionalIdentifier in additionalIdentifiers {
            let trimmedIdentifier = additionalIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedIdentifier.isEmpty else { continue }
            names.append(trimmedIdentifier)
            names.append(fileSystemSafeToken(trimmedIdentifier))
            names.append(normalizedToken(trimmedIdentifier))
            let identifierDigits = trimmedIdentifier.filter(\.isNumber)
            if identifierDigits.count >= 7 {
                names.append(String(identifierDigits))
                names.append("\(identifierDigits)@s.whatsapp.net")
            }
        }

        var seen = Set<String>()
        return names
            .filter { $0.count >= 5 }
            .filter { seen.insert($0).inserted }
            .sorted { $0.count > $1.count }
    }

    private func fileSystemSafeToken(_ value: String) -> String {
        value.map { character in
            character == "/" || character == ":" ? "_" : character
        }
        .map(String.init)
        .joined()
    }

    private func normalizedToken(_ value: String) -> String {
        value
            .lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private static let profileDirectories = [
        "Media/Profile",
        "Profile Pictures",
        "ProfilePictures",
        "Profile Photos",
        "ProfilePhotos",
        "Profiles",
        "Profile",
        "Avatars",
        "Media/Profile Pictures",
        "Media/ProfilePictures",
        "Library/Caches/Profile Pictures",
        "Library/Caches/ProfilePictures",
        "Library/Caches/Profile Photos",
        "Library/Caches/ProfilePhotos",
        "Library/Caches/Profiles",
        "Library/Caches/Profile",
        "Library/Caches/Avatars"
    ]
    private static let imageExtensions = ["thumb", "jpg", "jpeg", "png", "heic", "heif", "j"]
    private static let maxProfilePictureLookupIdentifiers = 48
    private static let maxProfilePictureItemRowsPerLookup = 32
}

private extension Array {
    func chunked(maxCount: Int) -> [[Element]] {
        guard maxCount > 0, !isEmpty else { return [] }
        return stride(from: 0, to: count, by: maxCount).map { startIndex in
            Array(self[startIndex..<Swift.min(startIndex + maxCount, count)])
        }
    }
}

private final class ContactsV2Resolver {
    private var database: OpaquePointer?
    private var identitiesByJID: [String: ContactIdentity] = [:]
    private var loadedJIDs = Set<String>()
    private var didDiscoverMissingContactsTable = false

    init?(archiveRootURL: URL) {
        let contactsURL = archiveRootURL.appendingPathComponent("ContactsV2.sqlite")
        guard FileManager.default.fileExists(atPath: contactsURL.path) else {
            return nil
        }

        var connection: OpaquePointer?
        let result = sqlite3_open_v2(contactsURL.path, &connection, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let connection else {
            if let connection {
                sqlite3_close(connection)
            }
            return nil
        }

        database = connection
        do {
            try execute("PRAGMA query_only = ON")
        } catch {
            sqlite3_close(connection)
            database = nil
            return nil
        }
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    func identity(for jid: String?) -> ContactIdentity? {
        guard let key = normalizedJID(jid) else { return nil }
        return identitiesByJID[key]
    }

    func loadIdentities(for jids: [String?]) throws {
        let requestedJIDs = Set(jids.compactMap(normalizedJID))
        let unloadedJIDs = requestedJIDs.subtracting(loadedJIDs)
        guard !unloadedJIDs.isEmpty, !didDiscoverMissingContactsTable else { return }
        guard let database else { return }
        guard try tableExists("ZWAADDRESSBOOKCONTACT") else {
            didDiscoverMissingContactsTable = true
            loadedJIDs.formUnion(unloadedJIDs)
            return
        }

        let columns = try columns(in: "ZWAADDRESSBOOKCONTACT")
        guard columns.contains("Z_PK") else {
            loadedJIDs.formUnion(unloadedJIDs)
            return
        }

        let lookupColumns = [
            "ZWHATSAPPID",
            "ZLID",
            "ZIDENTIFIER",
            "ZPHONENUMBER",
            "ZLOCALIZEDPHONENUMBER"
        ].filter { columns.contains($0) }
        guard !lookupColumns.isEmpty else {
            loadedJIDs.formUnion(unloadedJIDs)
            return
        }

        let lookupValues = Array(Set(unloadedJIDs.flatMap(contactLookupValues(for:)))).sorted()
        guard !lookupValues.isEmpty else {
            loadedJIDs.formUnion(unloadedJIDs)
            return
        }

        #if DEBUG
        let lookupStart = Date()
        #endif
        var fetchedContactKeys = Set<Int64>()
        var candidatesByJID: [String: [ContactIdentity]] = [:]

        let bindLimit = max(Int(sqlite3_limit(database, SQLITE_LIMIT_VARIABLE_NUMBER, -1)), 1)
        let lookupChunkSize = max(1, min(600, bindLimit / max(lookupColumns.count, 1)))
        let lookupChunks = lookupValues.chunked(maxCount: lookupChunkSize)

        for chunk in lookupChunks {
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ", ")
            let whereSQL = lookupColumns
                .map { "\($0) IN (\(placeholders))" }
                .joined(separator: " OR ")
            let sql = """
                SELECT
                    Z_PK,
                    \(select("ZWHATSAPPID", columns: columns)),
                    \(select("ZLID", columns: columns)),
                    \(select("ZIDENTIFIER", columns: columns)),
                    \(select("ZPHONENUMBER", columns: columns)),
                    \(select("ZLOCALIZEDPHONENUMBER", columns: columns)),
                    \(select("ZFULLNAME", columns: columns)),
                    \(select("ZGIVENNAME", columns: columns)),
                    \(select("ZLASTNAME", columns: columns)),
                    \(select("ZBUSINESSNAME", columns: columns)),
                    \(select("ZHIGHLIGHTEDNAME", columns: columns)),
                    \(select("ZUSERNAME", columns: columns))
                FROM ZWAADDRESSBOOKCONTACT
                WHERE \(whereSQL)
                """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }

            var bindIndex: Int32 = 1
            for _ in lookupColumns {
                for value in chunk {
                    sqlite3_bind_text(statement, bindIndex, value, -1, sqliteTransient)
                    bindIndex += 1
                }
            }

            var stepResult = sqlite3_step(statement)
            while stepResult == SQLITE_ROW {
                let contactKey = sqlite3_column_int64(statement, 0)
                guard fetchedContactKeys.insert(contactKey).inserted else {
                    stepResult = sqlite3_step(statement)
                    continue
                }
                let profilePhotoIdentifiers = [
                    string(statement, 1),
                    string(statement, 2),
                    string(statement, 3),
                    string(statement, 4),
                    string(statement, 5)
                ].compactMap { value -> String? in
                    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed?.isEmpty == false ? trimmed : nil
                }
                let identity = ContactIdentity(
                    key: "contactsV2:\(contactKey)",
                    displayName: displayName(
                        fullName: string(statement, 6),
                        givenName: string(statement, 7),
                        lastName: string(statement, 8),
                        businessName: string(statement, 9),
                        highlightedName: string(statement, 10),
                        username: string(statement, 11)
                    ),
                    profilePhotoIdentifiers: profilePhotoIdentifiers
                )

                for jid in profilePhotoIdentifiers.compactMap(normalizedJID) where unloadedJIDs.contains(jid) {
                    candidatesByJID[jid, default: []].append(identity)
                }
                stepResult = sqlite3_step(statement)
            }
            try throwIfStatementFailed(stepResult)
        }

        let resolvedIdentities = candidatesByJID.compactMapValues { identities -> ContactIdentity? in
            let keys = Set(identities.map(\.key))
            guard keys.count == 1 else { return nil }
            return identities[0]
        }
        identitiesByJID.merge(resolvedIdentities) { current, _ in current }
        loadedJIDs.formUnion(unloadedJIDs)
        #if DEBUG
        print("[ArchiveOpen] ContactsV2 lookup: \(FetchChatsDebugTimer.milliseconds(since: lookupStart)) ms requested=\(requestedJIDs.count) values=\(lookupValues.count) chunks=\(lookupChunks.count) resolved=\(resolvedIdentities.count)")
        #endif
    }

    private func contactLookupValues(for jid: String) -> [String] {
        let trimmed = jid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }

        var values = [trimmed]
        if let localPart = trimmed.split(separator: "@", maxSplits: 1).first.map(String.init), !localPart.isEmpty {
            values.append(localPart)
            let digits = localPart.filter(\.isNumber)
            if digits.count >= 6 {
                values.append(String(digits))
            }
        }
        return Array(Set(values))
    }

    private func displayName(
        fullName: String?,
        givenName: String?,
        lastName: String?,
        businessName: String?,
        highlightedName: String?,
        username: String?
    ) -> String? {
        let combinedName = [givenName, lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return DisplayNameSanitizer.friendlyName(fullName)
            ?? DisplayNameSanitizer.friendlyName(combinedName)
            ?? DisplayNameSanitizer.friendlyName(businessName)
            ?? DisplayNameSanitizer.friendlyName(highlightedName)
            ?? DisplayNameSanitizer.friendlyName(username)
    }

    private func normalizedJID(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !trimmed.isEmpty else {
            return nil
        }
        guard !trimmed.contains(";"), !trimmed.contains(",") else {
            return nil
        }
        if trimmed.contains("@s.whatsapp.net") || trimmed.contains("@lid") {
            return trimmed
        }
        let digits = trimmed.filter(\.isNumber)
        if digits.count >= 6 {
            return "\(digits)@s.whatsapp.net"
        }
        return nil
    }

    private func select(_ column: String, columns: Set<String>) -> String {
        columns.contains(column) ? column : "NULL"
    }

    private func tableExists(_ table: String) throws -> Bool {
        let statement = try prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, table, -1, sqliteTransient)
        let result = sqlite3_step(statement)
        if result == SQLITE_ROW {
            return true
        }
        if result == SQLITE_DONE {
            return false
        }
        throw WhatsAppDatabaseError.queryFailed(lastErrorMessage)
    }

    private func columns(in table: String) throws -> Set<String> {
        let statement = try prepare("PRAGMA table_info(\(table))")
        defer { sqlite3_finalize(statement) }

        var columns = Set<String>()
        var stepResult = sqlite3_step(statement)
        while stepResult == SQLITE_ROW {
            if let column = string(statement, 1) {
                columns.insert(column)
            }
            stepResult = sqlite3_step(statement)
        }
        try throwIfStatementFailed(stepResult)
        return columns
    }

    private func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? lastErrorMessage
            sqlite3_free(errorMessage)
            throw WhatsAppDatabaseError.queryFailed(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw WhatsAppDatabaseError.queryFailed(lastErrorMessage)
        }
        return statement
    }

    private func throwIfStatementFailed(_ result: Int32) throws {
        guard result == SQLITE_DONE else {
            throw WhatsAppDatabaseError.queryFailed(lastErrorMessage)
        }
    }

    private var lastErrorMessage: String {
        guard let database else { return "database is not open" }
        return String(cString: sqlite3_errmsg(database))
    }

    private func string(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: text)
    }
}

enum WhatsAppDatabaseError: LocalizedError {
    case missingDatabase(URL)
    case invalidSchema(String)
    case openFailed(String)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingDatabase(let url):
            return "Missing ChatStorage.sqlite at \(url.path)"
        case .invalidSchema(let message):
            return "Invalid WhatsApp database schema: \(message)"
        case .openFailed(let message):
            return "Could not open ChatStorage.sqlite read-only: \(message)"
        case .queryFailed(let message):
            return "SQLite query failed: \(message)"
        }
    }
}

final class WhatsAppDatabase: @unchecked Sendable {
    private let databaseURL: URL
    private let archiveRootURL: URL
    private let securityScopedURL: URL?
    private let didStartSecurityScope: Bool
    private var database: OpaquePointer?
    private var messageColumns: Set<String> = []
    private var mediaSchema: MediaSchema?
    private var canJoinProfilePushNames = false
    private var contactsResolver: ContactsV2Resolver?

    init(databaseURL: URL, archiveRootURL: URL? = nil, securityScopedURL: URL? = nil) throws {
        self.databaseURL = databaseURL
        self.archiveRootURL = archiveRootURL ?? databaseURL.deletingLastPathComponent()
        self.securityScopedURL = securityScopedURL
        self.didStartSecurityScope = securityScopedURL?.startAccessingSecurityScopedResource() ?? false
        #if DEBUG
        var openTimer = DatabaseOpenDebugTimer()
        #endif

        do {
            guard FileManager.default.fileExists(atPath: databaseURL.path) else {
                throw WhatsAppDatabaseError.missingDatabase(databaseURL)
            }

            let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
            var connection: OpaquePointer?
            let result = sqlite3_open_v2(databaseURL.path, &connection, flags, nil)
            guard result == SQLITE_OK, let connection else {
                let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
                if let connection {
                    sqlite3_close(connection)
                }
                throw WhatsAppDatabaseError.openFailed(message)
            }

            database = connection
            try execute("PRAGMA query_only = ON")
            #if DEBUG
            openTimer.mark("opening ChatStorage.sqlite")
            #endif
            try validateSchema()
            messageColumns = try columns(in: "ZWAMESSAGE")
            mediaSchema = try discoverMediaSchema()
            canJoinProfilePushNames = try discoverProfilePushNameJoin()
            #if DEBUG
            openTimer.mark("ChatStorage schema discovery")
            #endif
            #if DEBUG
            let contactsStart = Date()
            #endif
            contactsResolver = ContactsV2Resolver(archiveRootURL: self.archiveRootURL)
            #if DEBUG
            let contactsMilliseconds = Date().timeIntervalSince(contactsStart) * 1000
            print("[ArchiveOpen] opening ContactsV2.sqlite: \(Int(contactsMilliseconds)) ms available=\(contactsResolver != nil)")
            #endif
        } catch {
            if let database {
                sqlite3_close(database)
                self.database = nil
            }
            if didStartSecurityScope {
                securityScopedURL?.stopAccessingSecurityScopedResource()
            }
            throw error
        }
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
        if didStartSecurityScope {
            securityScopedURL?.stopAccessingSecurityScopedResource()
        }
    }

    func fetchChats() throws -> [ChatSummary] {
        #if DEBUG
        var timer = FetchChatsDebugTimer()
        #endif
        let messageFlagsSystemSQL = systemMessageSQL(alias: "m")
        let messageFlagsStatusStorySQL = statusStoryMessageSQL(messageAlias: "m", chatAlias: "c_flag")
        let messageFlagsUserVisibleSQL = """
            (NOT \(messageFlagsSystemSQL)
            AND NOT \(messageFlagsStatusStorySQL)
            AND (
                \(textMessageSQL(alias: "m"))
                OR \(chatSummaryMediaEvidenceSQL(messageAlias: "m", mediaPresenceAlias: "media_presence"))
                OR \(callMessageSQL(alias: "m"))
            ))
            """
        let sql = """
            WITH message_flags AS (
                SELECT
                    m.Z_PK AS message_id,
                    m.ZCHATSESSION AS chat_id,
                    m.ZMESSAGEDATE AS message_date,
                    CASE WHEN \(messageFlagsSystemSQL) THEN 1 ELSE 0 END AS is_system,
                    CASE WHEN \(messageFlagsStatusStorySQL) THEN 1 ELSE 0 END AS is_status_story,
                    CASE WHEN \(messageFlagsUserVisibleSQL) THEN 1 ELSE 0 END AS is_user_visible
                FROM ZWAMESSAGE m
                \(chatSessionJoinSQL(alias: "c_flag"))
                \(mediaPresenceJoinSQL())
            ),
            message_aggregates AS (
                SELECT
                    chat_id,
                    COUNT(message_id) AS total_message_count,
                    COALESCE(SUM(is_user_visible), 0) AS user_visible_message_count,
                    COALESCE(SUM(is_system), 0) AS system_message_count,
                    COALESCE(SUM(is_status_story), 0) AS status_story_message_count,
                    MAX(CASE WHEN is_user_visible = 1 THEN message_date ELSE NULL END) AS latest_user_visible_message_date,
                    MAX(message_date) AS latest_any_message_date
                FROM message_flags
                GROUP BY chat_id
            )
            SELECT
                c.Z_PK,
                c.ZCONTACTJID,
                c.ZCONTACTIDENTIFIER,
                c.ZPARTNERNAME,
                CASE
                    WHEN c.ZLASTMESSAGEDATE BETWEEN 0 AND 1500000000
                    THEN c.ZLASTMESSAGEDATE
                    ELSE NULL
                END AS sanitized_last_message_date,
                COALESCE(a.total_message_count, 0) AS total_message_count,
                COALESCE(a.user_visible_message_count, 0) AS user_visible_message_count,
                COALESCE(a.system_message_count, 0) AS system_message_count,
                COALESCE(a.status_story_message_count, 0) AS status_story_message_count,
                a.latest_user_visible_message_date,
                a.latest_any_message_date
            FROM ZWACHATSESSION c
            LEFT JOIN message_aggregates a ON a.chat_id = c.Z_PK
            ORDER BY COALESCE(latest_user_visible_message_date, latest_any_message_date, sanitized_last_message_date, 0) DESC, c.Z_PK ASC
            """

        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        #if DEBUG
        timer.mark("fetchChats prepare mediaPresenceJoin=\(shouldJoinMediaPresenceForChatSummary ? 1 : 0)")
        #endif

        var rawRows: [RawChatSummaryRow] = []
        var stepResult = sqlite3_step(statement)
        while stepResult == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            rawRows.append(
                RawChatSummaryRow(
                    id: id,
                    contactJID: string(statement, 1),
                    contactIdentifier: string(statement, 2),
                    partnerName: string(statement, 3),
                    sanitizedLastMessageDate: date(statement, 4),
                    totalMessageCount: max(Int(sqlite3_column_int64(statement, 5)), 0),
                    userVisibleMessageCount: max(Int(sqlite3_column_int64(statement, 6)), 0),
                    systemMessageCount: max(Int(sqlite3_column_int64(statement, 7)), 0),
                    statusStoryMessageCount: max(Int(sqlite3_column_int64(statement, 8)), 0),
                    latestUserVisibleMessageDate: date(statement, 9),
                    latestAnyMessageDate: date(statement, 10)
                )
            )
            stepResult = sqlite3_step(statement)
        }

        try throwIfStatementFailed(stepResult)
        #if DEBUG
        let totalMessages = rawRows.reduce(0) { $0 + $1.totalMessageCount }
        let statusStoryMessages = rawRows.reduce(0) { $0 + $1.statusStoryMessageCount }
        timer.mark("stories/status fetch sessions=\(rawRows.count) messages=\(totalMessages) statusStoryMessages=\(statusStoryMessages)")
        let contactStart = Date()
        #endif
        do {
            try contactsResolver?.loadIdentities(for: rawRows.map(\.contactJID))
        } catch {
            #if DEBUG
            print("[ArchiveOpen] ContactsV2 enrichment skipped after lookup failure")
            #endif
        }

        let rows = rawRows.map { row -> ChatSummaryRow in
            let contactIdentity = contactsResolver?.identity(for: row.contactJID)
            let title = DisplayNameSanitizer.friendlyName(contactIdentity?.displayName)
                ?? DisplayNameSanitizer.friendlyName(row.partnerName)
                ?? DisplayNameSanitizer.friendlyName(row.contactIdentifier)
                ?? (isGroupJID(row.contactJID) ? "Group chat" : "Unknown chat")
            let isStatusStoryOnlySession = row.totalMessageCount > 0 && row.statusStoryMessageCount == row.totalMessageCount
            let messageCount = isStatusStoryOnlySession ? row.statusStoryMessageCount : row.userVisibleMessageCount
            let fallbackMessageDate = row.latestUserVisibleMessageDate ?? row.latestAnyMessageDate ?? row.sanitizedLastMessageDate

            return ChatSummaryRow(
                id: row.id,
                identityKey: isStatusStoryOnlySession
                    ? "status-stories"
                    : chatIdentityKey(id: row.id, contactJID: row.contactJID, contactIdentity: contactIdentity),
                contactJID: row.contactJID,
                contactIdentifier: row.contactIdentifier,
                profilePhotoIdentifiers: contactIdentity?.profilePhotoIdentifiers ?? [],
                partnerName: row.partnerName,
                title: title,
                profilePhotoURL: nil,
                messageCount: messageCount,
                totalMessageCount: row.totalMessageCount,
                userVisibleMessageCount: row.userVisibleMessageCount,
                systemMessageCount: row.systemMessageCount,
                statusStoryMessageCount: row.statusStoryMessageCount,
                latestUserVisibleMessageDate: row.latestUserVisibleMessageDate,
                latestAnyMessageDate: row.latestAnyMessageDate,
                fallbackMessageDate: fallbackMessageDate
            )
        }

        #if DEBUG
        print("[ArchiveOpen] contact enrichment: \(FetchChatsDebugTimer.milliseconds(since: contactStart)) ms lookups=\(rawRows.count)")
        timer.mark("contact enrichment")
        let mergeStart = Date()
        #endif
        let summaries = mergedChatSummaries(from: rows)
        #if DEBUG
        let statusStorySummaries = summaries.filter { $0.classification == .statusStoryFragment }.count
        let normalSummaries = summaries.count - statusStorySummaries
        print("[ArchiveOpen] chat classification + fragment filtering: \(FetchChatsDebugTimer.milliseconds(since: mergeStart)) ms sourceSessions=\(rows.count) visible=\(summaries.count) normal=\(normalSummaries) stories=\(statusStorySummaries)")
        timer.mark("fetchChats total")
        #endif
        return summaries
    }

    private func chatIdentityKey(id: Int64, contactJID: String?, contactIdentity: ContactIdentity?) -> String {
        if let contactIdentity {
            return contactIdentity.key
        }
        if let contactJID = contactJID?.trimmingCharacters(in: .whitespacesAndNewlines), !contactJID.isEmpty {
            return "jid:\(contactJID)"
        }
        return "session:\(id)"
    }

    private func isGroupJID(_ value: String?) -> Bool {
        value?.contains("@g.us") == true
    }

    private func userVisibleMessageSQL(messageAlias: String, chatAlias: String) -> String {
        """
        (NOT \(systemMessageSQL(alias: messageAlias))
        AND NOT \(statusStoryMessageSQL(messageAlias: messageAlias, chatAlias: chatAlias))
        AND (\(textMessageSQL(alias: messageAlias)) OR \(mediaEvidenceSQL(alias: messageAlias)) OR \(callMessageSQL(alias: messageAlias))))
        """
    }

    private func textMessageSQL(alias: String) -> String {
        "(\(alias).ZTEXT IS NOT NULL AND TRIM(\(alias).ZTEXT) <> '')"
    }

    private func mediaEvidenceSQL(alias: String) -> String {
        var predicates: [String] = []
        if mediaSchema?.canJoinMessages == true {
            predicates.append("EXISTS (SELECT 1 FROM ZWAMEDIAITEM chat_media WHERE chat_media.ZMESSAGE = \(alias).Z_PK)")
        }
        if messageColumns.contains("ZMEDIAITEM") {
            predicates.append("\(alias).ZMEDIAITEM IS NOT NULL")
        }
        if messageColumns.contains("ZMESSAGETYPE") {
            predicates.append("\(alias).ZMESSAGETYPE IN (1, 2, 3, 4, 5, 7, 8, 15)")
        }
        guard !predicates.isEmpty else {
            return "0"
        }
        return "(\(predicates.joined(separator: " OR ")))"
    }

    private func chatSummaryMediaEvidenceSQL(messageAlias: String, mediaPresenceAlias: String) -> String {
        var predicates: [String] = []
        if shouldJoinMediaPresenceForChatSummary {
            predicates.append("\(mediaPresenceAlias).ZMESSAGE IS NOT NULL")
        }
        if messageColumns.contains("ZMEDIAITEM") {
            predicates.append("\(messageAlias).ZMEDIAITEM IS NOT NULL")
        }
        if messageColumns.contains("ZMESSAGETYPE") {
            predicates.append("\(messageAlias).ZMESSAGETYPE IN (1, 2, 3, 4, 5, 7, 8, 15)")
        }
        guard !predicates.isEmpty else {
            return "0"
        }
        return "(\(predicates.joined(separator: " OR ")))"
    }

    private var shouldJoinMediaPresenceForChatSummary: Bool {
        mediaSchema?.canJoinMessages == true && !messageColumns.contains("ZMEDIAITEM")
    }

    private func photoMediaSQL() -> String {
        let path = "lower(COALESCE(mi.ZMEDIALOCALPATH, mi.ZMEDIAURL, mi.ZTITLE, ''))"
        return """
        (m.ZMESSAGETYPE = 1
        OR \(path) LIKE '%.jpg'
        OR \(path) LIKE '%.jpeg'
        OR \(path) LIKE '%.png'
        OR \(path) LIKE '%.heic'
        OR \(path) LIKE '%.webp'
        OR \(path) LIKE '%.gif')
        """
    }

    private func videoMediaSQL() -> String {
        let path = "lower(COALESCE(mi.ZMEDIALOCALPATH, mi.ZMEDIAURL, mi.ZTITLE, ''))"
        var predicates = [
            "m.ZMESSAGETYPE = 2",
            "\(path) LIKE '%.mp4'",
            "\(path) LIKE '%.mov'",
            "\(path) LIKE '%.m4v'"
        ]
        if mediaSchema?.columns.contains("ZMOVIEDURATION") == true {
            predicates.append("(m.ZMESSAGETYPE = 4 AND mi.ZMOVIEDURATION IS NOT NULL AND mi.ZMOVIEDURATION > 0)")
        }
        return "(\(predicates.joined(separator: "\n        OR ")))"
    }

    private func audioMediaSQL(includeVoiceMessages: Bool = true) -> String {
        let path = "lower(COALESCE(mi.ZMEDIALOCALPATH, mi.ZMEDIAURL, mi.ZTITLE, ''))"
        let audioSQL = """
        (m.ZMESSAGETYPE = 3
        OR \(path) LIKE '%.aac'
        OR \(path) LIKE '%.caf'
        OR \(path) LIKE '%.m4a'
        OR \(path) LIKE '%.mp3'
        OR \(path) LIKE '%.ogg'
        OR \(path) LIKE '%.opus'
        OR \(path) LIKE '%.wav')
        """
        guard !includeVoiceMessages else { return audioSQL }
        return "(\(audioSQL) AND NOT \(voiceMessageAudioSQL()))"
    }

    private func documentMediaSQL() -> String {
        let path = "lower(COALESCE(mi.ZMEDIALOCALPATH, mi.ZMEDIAURL, mi.ZTITLE, ''))"
        return """
        (m.ZMESSAGETYPE = 8
        OR \(path) LIKE '%.pdf'
        OR \(path) LIKE '%.doc'
        OR \(path) LIKE '%.docx'
        OR \(path) LIKE '%.xls'
        OR \(path) LIKE '%.xlsx'
        OR \(path) LIKE '%.ppt'
        OR \(path) LIKE '%.pptx'
        OR \(path) LIKE '%.txt'
        OR \(path) LIKE '%.rtf'
        OR \(path) LIKE '%.zip')
        """
    }

    private func mediaLibraryCandidateSQL() -> String {
        "(\(photoMediaSQL()) OR \(videoMediaSQL()) OR \(audioMediaSQL(includeVoiceMessages: false)) OR \(documentMediaSQL()))"
    }

    private func voiceMessageAudioSQL() -> String {
        guard mediaSchema?.columns.contains("ZMEDIAORIGIN") == true else {
            return "0"
        }
        return "(mi.ZMEDIAORIGIN = 1)"
    }

    private func callMessageSQL(alias: String) -> String {
        guard messageColumns.contains("ZMESSAGETYPE") else {
            return "0"
        }
        return "(\(alias).ZMESSAGETYPE IN (59, 66))"
    }

    private func systemMessageSQL(alias: String) -> String {
        var predicates: [String] = []
        if messageColumns.contains("ZMESSAGETYPE") {
            predicates.append("\(alias).ZMESSAGETYPE IN (6, 10)")
        }
        if messageColumns.contains("ZTEXT") {
            let text = "lower(COALESCE(\(alias).ZTEXT, ''))"
            predicates.append("(\(text) LIKE '%security code%' AND \(text) LIKE '%changed%' AND \(text) LIKE '%learn more%')")
        }
        guard !predicates.isEmpty else { return "0" }
        return "(\(predicates.joined(separator: " OR ")))"
    }

    private func statusStoryMessageSQL(messageAlias: String, chatAlias: String) -> String {
        var predicates: [String] = []
        if messageColumns.contains("ZFROMJID") {
            predicates.append("\(messageAlias).ZFROMJID = 'status@broadcast'")
        }
        predicates.append("\(chatAlias).ZCONTACTJID = 'status@broadcast'")
        guard !predicates.isEmpty else { return "0" }
        return "(\(messageAlias).ZISFROMME = 0 AND (\(predicates.joined(separator: " OR "))))"
    }

    func fetchMessages(
        sessionIDs: [Int64],
        limit: Int = 500,
        includeStatusStoryMessages: Bool = false
    ) throws -> [MessageRow] {
        let sessionIDs = normalizedSessionIDs(sessionIDs)
        let placeholders = sessionPlaceholders(for: sessionIDs)
        let messageVisibilityFilterSQL = messageVisibilityFilterSQL(
            includeStatusStoryMessages: includeStatusStoryMessages
        )
        let sql = """
            SELECT *
            FROM (
                \(messageRowSelectSQL())
                FROM ZWAMESSAGE m
                \(chatSessionJoinSQL())
                \(mediaJoinSQL())
                \(groupMemberJoinSQL())
                WHERE m.ZCHATSESSION IN (\(placeholders))
                  AND \(messageVisibilityFilterSQL)
                ORDER BY m.ZMESSAGEDATE DESC, m.Z_PK DESC
                LIMIT ?
            )
            ORDER BY ZMESSAGEDATE ASC, Z_PK ASC
            """

        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindSessionIDs(sessionIDs, to: statement)
        sqlite3_bind_int(statement, Int32(sessionIDs.count + 1), Int32(limit))

        return try readMessages(from: statement)
    }

    func fetchOlderMessages(
        sessionIDs: [Int64],
        before cursor: MessagePaginationCursor,
        limit: Int = 500,
        includeStatusStoryMessages: Bool = false
    ) throws -> [MessageRow] {
        let sessionIDs = normalizedSessionIDs(sessionIDs)
        let placeholders = sessionPlaceholders(for: sessionIDs)
        let messageVisibilityFilterSQL = messageVisibilityFilterSQL(
            includeStatusStoryMessages: includeStatusStoryMessages
        )
        let sql = """
            \(messageRowSelectSQL())
            FROM ZWAMESSAGE m
            \(chatSessionJoinSQL())
            \(mediaJoinSQL())
            \(groupMemberJoinSQL())
            WHERE m.ZCHATSESSION IN (\(placeholders))
              AND \(messageVisibilityFilterSQL)
              AND (
                m.ZMESSAGEDATE < ?
                OR (m.ZMESSAGEDATE = ? AND m.Z_PK < ?)
              )
            ORDER BY m.ZMESSAGEDATE DESC, m.Z_PK DESC
            LIMIT ?
            """

        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        let cursorDate = cursor.messageDate.timeIntervalSinceReferenceDate
        bindSessionIDs(sessionIDs, to: statement)
        let cursorDateIndex = Int32(sessionIDs.count + 1)
        sqlite3_bind_double(statement, cursorDateIndex, cursorDate)
        sqlite3_bind_double(statement, cursorDateIndex + 1, cursorDate)
        sqlite3_bind_int64(statement, cursorDateIndex + 2, cursor.messageID)
        sqlite3_bind_int(statement, cursorDateIndex + 3, Int32(limit))

        let descendingMessages = try readMessages(from: statement)
        return Array(descendingMessages.reversed())
    }

    private func messageVisibilityFilterSQL(includeStatusStoryMessages: Bool) -> String {
        includeStatusStoryMessages
            ? statusStoryMessageSQL(messageAlias: "m", chatAlias: "c")
            : userVisibleMessageSQL(messageAlias: "m", chatAlias: "c")
    }

    func fetchChatMediaItems(
        sessionIDs: [Int64],
        filter: ChatMediaFilter,
        includeStatusStoriesInAll: Bool,
        limit: Int = 300
    ) throws -> [ChatMediaItem] {
        try fetchChatMediaLibraryPage(
            sessionIDs: sessionIDs,
            filter: filter,
            includeStatusStoriesInAll: includeStatusStoriesInAll,
            limit: limit
        ).items
    }

    func fetchChatMediaLibraryPage(
        sessionIDs: [Int64],
        filter: ChatMediaFilter,
        includeStatusStoriesInAll _: Bool,
        limit: Int = 300
    ) throws -> ChatMediaLibraryPage {
        guard mediaSchema?.canJoinMessages == true else {
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

        let sessionIDs = normalizedSessionIDs(sessionIDs)
        let placeholders = sessionPlaceholders(for: sessionIDs)
        let statusStorySQL = statusStoryMessageSQL(messageAlias: "m", chatAlias: "c")
        let candidateSQL = mediaLibraryCandidateSQL()
        let filterSQL: String
        switch filter {
        case .all:
            filterSQL = "NOT \(statusStorySQL) AND \(candidateSQL)"
        case .photos:
            filterSQL = "NOT \(statusStorySQL) AND \(photoMediaSQL())"
        case .videos:
            filterSQL = "NOT \(statusStorySQL) AND \(videoMediaSQL())"
        case .documents:
            filterSQL = "NOT \(statusStorySQL) AND \(documentMediaSQL())"
        }

        let totalRowsMatchingFilter = try countMediaRows(
            sessionIDs: sessionIDs,
            placeholders: placeholders,
            filterSQL: filterSQL
        )
        let statusStoryRowsExcluded = try countMediaRows(
            sessionIDs: sessionIDs,
            placeholders: placeholders,
            filterSQL: statusStorySQL
        )
        let scanLimit = max(limit, min(limit * 10, 5_000))
        let sql = """
            SELECT
                m.Z_PK,
                m.ZMESSAGEDATE,
                \(messageTypeSelectSQL()) AS message_type,
                \(groupEventTypeSelectSQL()) AS group_event_type,
                \(statusStorySQL) AS is_status_story,
                \(mediaSelectSQL())
            FROM ZWAMESSAGE m
            \(chatSessionJoinSQL())
            \(mediaJoinSQL())
            WHERE m.ZCHATSESSION IN (\(placeholders))
              AND mi.Z_PK IS NOT NULL
              AND \(filterSQL)
            ORDER BY
                CASE
                    WHEN mi.ZMEDIALOCALPATH IS NOT NULL AND TRIM(mi.ZMEDIALOCALPATH) <> '' THEN 0
                    ELSE 1
                END,
                m.ZMESSAGEDATE DESC,
                m.Z_PK DESC
            LIMIT ?
            """

        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindSessionIDs(sessionIDs, to: statement)
        sqlite3_bind_int(statement, Int32(sessionIDs.count + 1), Int32(scanLimit))

        var items: [ChatMediaItem] = []
        var scannedMedia: [MediaMetadata] = []
        var stepResult = sqlite3_step(statement)
        while stepResult == SQLITE_ROW {
            let messageID = sqlite3_column_int64(statement, 0)
            let isStatusStory = sqlite3_column_int(statement, 4) != 0
            guard let media = mediaMetadata(
                from: statement,
                startingAt: 5,
                messageType: int(statement, 2),
                groupEventType: int(statement, 3),
                source: isStatusStory ? .statusStory : .normal
            ) else {
                stepResult = sqlite3_step(statement)
                continue
            }
            scannedMedia.append(media)

            guard shouldIncludeInMediaLibrary(media, filter: filter) else {
                stepResult = sqlite3_step(statement)
                continue
            }

            items.append(
                ChatMediaItem(
                    id: "\(messageID)-\(media.itemID ?? 0)",
                    messageID: messageID,
                    messageDate: date(statement, 1),
                    media: media
                )
            )
            stepResult = sqlite3_step(statement)
        }

        try throwIfStatementFailed(stepResult)
        let sortedItems = prioritizedMediaLibraryItems(items, limit: limit)
        return ChatMediaLibraryPage(
            items: sortedItems,
            summary: mediaLoadSummary(
                totalRowsMatchingFilter: totalRowsMatchingFilter,
                rowsScanned: scannedMedia.count,
                displayedItems: sortedItems,
                statusStoryRowsExcluded: statusStoryRowsExcluded,
                scanLimit: scanLimit
            )
        )
    }

    private func countMediaRows(
        sessionIDs: [Int64],
        placeholders: String,
        filterSQL: String
    ) throws -> Int {
        let sql = """
            SELECT COUNT(*)
            FROM ZWAMESSAGE m
            \(chatSessionJoinSQL())
            \(mediaJoinSQL())
            WHERE m.ZCHATSESSION IN (\(placeholders))
              AND mi.Z_PK IS NOT NULL
              AND \(filterSQL)
            """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindSessionIDs(sessionIDs, to: statement)
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW else {
            try throwIfStatementFailed(result)
            return 0
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func shouldIncludeInMediaLibrary(
        _ media: MediaMetadata,
        filter: ChatMediaFilter
    ) -> Bool {
        switch filter {
        case .all:
            guard media.source != .statusStory else { return false }
            return isMediaLibraryDisplayable(media.kind)
        case .photos:
            return media.source != .statusStory && media.kind == .photo
        case .videos:
            return media.source != .statusStory && (media.kind == .video || media.kind == .videoMessage)
        case .documents:
            return media.source != .statusStory && media.kind == .document
        }
    }

    private func isMediaLibraryDisplayable(_ kind: MediaAttachmentKind) -> Bool {
        switch kind {
        case .photo, .video, .videoMessage, .audio, .sticker, .document:
            return true
        case .voiceMessage, .contact, .location, .linkPreview, .call, .callOrSystem, .system, .deleted, .media:
            return false
        }
    }

    private func prioritizedMediaLibraryItems(_ items: [ChatMediaItem], limit: Int) -> [ChatMediaItem] {
        Array(
            items.sorted { lhs, rhs in
                if lhs.media.isFileAvailableInArchive != rhs.media.isFileAvailableInArchive {
                    return lhs.media.isFileAvailableInArchive
                }
                switch (lhs.messageDate, rhs.messageDate) {
                case let (lhsDate?, rhsDate?):
                    if lhsDate != rhsDate {
                        return lhsDate > rhsDate
                    }
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    break
                }
                return lhs.messageID > rhs.messageID
            }
            .prefix(limit)
        )
    }

    private func mediaLoadSummary(
        totalRowsMatchingFilter: Int,
        rowsScanned: Int,
        displayedItems: [ChatMediaItem],
        statusStoryRowsExcluded: Int,
        scanLimit: Int
    ) -> ChatMediaLoadSummary {
        ChatMediaLoadSummary(
            totalRowsMatchingFilter: totalRowsMatchingFilter,
            rowsScanned: rowsScanned,
            displayedRows: displayedItems.count,
            rowsWithLocalPath: displayedItems.filter { $0.media.localPath?.isEmpty == false }.count,
            photoRows: displayedItems.filter { $0.media.kind == .photo || $0.media.kind == .sticker }.count,
            videoRows: displayedItems.filter { $0.media.kind == .video || $0.media.kind == .videoMessage }.count,
            audioRows: displayedItems.filter { $0.media.kind == .audio }.count,
            otherRows: displayedItems.filter { item in
                item.media.kind != .photo
                    && item.media.kind != .sticker
                    && item.media.kind != .video
                    && item.media.kind != .videoMessage
                    && item.media.kind != .audio
                    && item.media.kind != .voiceMessage
            }.count,
            resolvedFileURLRows: displayedItems.filter { $0.media.fileURL != nil }.count,
            existingFileRows: displayedItems.filter(\.media.isFileAvailableInArchive).count,
            readableFileRows: displayedItems.filter(\.media.isFileReadableInArchive).count,
            missingOrUnresolvedRows: displayedItems.filter { !$0.media.isFileAvailableInArchive || $0.media.fileURL == nil }.count,
            statusStoryRowsExcluded: statusStoryRowsExcluded,
            queryCapMayHideRows: totalRowsMatchingFilter > rowsScanned && rowsScanned >= scanLimit
        )
    }

    private func mergedChatSummaries(from rows: [ChatSummaryRow]) -> [ChatSummary] {
        let groupedRows = Dictionary(grouping: rows, by: \.identityKey)

        let drafts = groupedRows.values.map { group -> ChatSummaryDraft in
            let sortedGroup = group.sorted { lhs, rhs in
                switch (lhs.fallbackMessageDate, rhs.fallbackMessageDate) {
                case let (lhsDate?, rhsDate?):
                    if lhsDate != rhsDate {
                        return lhsDate > rhsDate
                    }
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    break
                }
                return lhs.id < rhs.id
            }
            let primary = sortedGroup[0]
            let sessionIDs = sortedGroup.map(\.id).sorted()
            let messageCount = sortedGroup.reduce(0) { $0 + $1.messageCount }
            let totalMessageCount = sortedGroup.reduce(0) { $0 + $1.totalMessageCount }
            let userVisibleMessageCount = sortedGroup.reduce(0) { $0 + $1.userVisibleMessageCount }
            let systemMessageCount = sortedGroup.reduce(0) { $0 + $1.systemMessageCount }
            let statusStoryMessageCount = sortedGroup.reduce(0) { $0 + $1.statusStoryMessageCount }
            let latestUserVisibleMessageDate = sortedGroup.compactMap(\.latestUserVisibleMessageDate).max()
            let latestAnyMessageDate = sortedGroup.compactMap(\.latestAnyMessageDate).max()
            let fallbackMessageDate = latestUserVisibleMessageDate
                ?? sortedGroup.compactMap(\.fallbackMessageDate).max()
                ?? latestAnyMessageDate
            let detailText = sessionIDs.count > 1
                ? "\(sessionIDs.count) linked archive entries, \(messageCount.formatted()) messages"
                : "\(messageCount.formatted()) messages"

            return ChatSummaryDraft(
                id: primary.id,
                sessionIDs: sessionIDs,
                contactJID: primary.contactJID,
                contactIdentifier: primary.contactIdentifier,
                profilePhotoIdentifiers: Array(Set(sortedGroup.flatMap(\.profilePhotoIdentifiers))).sorted(),
                partnerName: primary.partnerName,
                title: statusStoryMessageCount == totalMessageCount && totalMessageCount > 0 ? "Stories" : primary.title,
                profilePhotoURL: statusStoryMessageCount == totalMessageCount && totalMessageCount > 0
                    ? nil
                    : sortedGroup.compactMap(\.profilePhotoURL).first,
                detailText: detailText,
                latestUserVisibleMessageDate: latestUserVisibleMessageDate,
                latestAnyMessageDate: latestAnyMessageDate,
                fallbackMessageDate: fallbackMessageDate,
                searchableTitle: statusStoryMessageCount == totalMessageCount && totalMessageCount > 0 ? "Stories" : primary.title,
                activity: ChatActivityMetrics(
                    messageCount: messageCount,
                    totalMessageCount: totalMessageCount,
                    userVisibleMessageCount: userVisibleMessageCount,
                    systemMessageCount: systemMessageCount,
                    statusStoryMessageCount: statusStoryMessageCount
                )
            )
        }

        let visibleDrafts = drafts.filter { draft in
            baseClassification(for: draft.activity) == .normalConversation
        }
        let visibleDuplicateTitleCounts = Dictionary(grouping: visibleDrafts, by: \.title)
            .mapValues(\.count)

        let summaries = drafts.compactMap { draft -> ChatSummary? in
            let baseClassification = baseClassification(for: draft.activity)
            guard !isHiddenFromDefaultChatList(baseClassification) else {
                return nil
            }

            let classification: ChatSessionClassification
            if baseClassification == .normalConversation,
               visibleDuplicateTitleCounts[draft.title, default: 0] > 1 {
                classification = .separateConversation
            } else {
                classification = baseClassification
            }

            return ChatSummary(
                id: draft.id,
                sessionIDs: draft.sessionIDs,
                contactJID: draft.contactJID,
                contactIdentifier: draft.contactIdentifier,
                profilePhotoIdentifiers: draft.profilePhotoIdentifiers,
                partnerName: draft.partnerName,
                title: draft.title,
                detailText: detailText(for: draft, classification: classification),
                messageCount: draft.activity.messageCount,
                latestMessageDate: latestDisplayDate(for: draft, classification: classification),
                searchableTitle: draft.searchableTitle,
                classification: classification,
                profilePhotoURL: draft.profilePhotoURL
            )
        }

        return summaries.sorted(by: chatSummarySort)
    }

    private func baseClassification(for activity: ChatActivityMetrics) -> ChatSessionClassification {
        if activity.hasOnlyStatusStoryMessages {
            return .statusStoryFragment
        }
        if activity.hasUserVisibleMessages {
            return .normalConversation
        }
        if activity.totalMessageCount > 0, activity.systemMessageCount == activity.totalMessageCount {
            return .systemOnlyFragment
        }
        return .archiveFragment
    }

    private func isHiddenFromDefaultChatList(_ classification: ChatSessionClassification) -> Bool {
        switch classification {
        case .archiveFragment, .systemOnlyFragment, .unknown:
            return true
        case .normalConversation, .separateConversation, .statusStoryFragment:
            return false
        }
    }

    private func detailText(
        for draft: ChatSummaryDraft,
        classification: ChatSessionClassification
    ) -> String {
        switch classification {
        case .normalConversation:
            return draft.detailText
        case .separateConversation:
            return "Separate conversation, \(draft.detailText)"
        case .statusStoryFragment:
            return "Stories media, \(draft.detailText)"
        case .archiveFragment:
            return "Archive fragment, \(draft.detailText)"
        case .systemOnlyFragment:
            return "System-only archive fragment, \(draft.detailText)"
        case .unknown:
            return "Archive entry, \(draft.detailText)"
        }
    }

    private func latestDisplayDate(
        for draft: ChatSummaryDraft,
        classification: ChatSessionClassification
    ) -> Date? {
        switch classification {
        case .normalConversation, .separateConversation:
            return draft.latestUserVisibleMessageDate
        case .statusStoryFragment, .archiveFragment, .systemOnlyFragment, .unknown:
            return draft.latestAnyMessageDate ?? draft.fallbackMessageDate
        }
    }

    private func chatSummarySort(_ lhs: ChatSummary, _ rhs: ChatSummary) -> Bool {
        switch (lhs.latestMessageDate, rhs.latestMessageDate) {
        case let (lhsDate?, rhsDate?):
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            break
        }
        return lhs.id < rhs.id
    }

    private func normalizedSessionIDs(_ sessionIDs: [Int64]) -> [Int64] {
        let normalized = Array(Set(sessionIDs)).sorted()
        return normalized.isEmpty ? [-1] : normalized
    }

    private func sessionPlaceholders(for sessionIDs: [Int64]) -> String {
        Array(repeating: "?", count: sessionIDs.count).joined(separator: ", ")
    }

    private func bindSessionIDs(_ sessionIDs: [Int64], to statement: OpaquePointer) {
        for (index, sessionID) in sessionIDs.enumerated() {
            sqlite3_bind_int64(statement, Int32(index + 1), sessionID)
        }
    }

    private func messageRowSelectSQL() -> String {
        """
        SELECT
            m.Z_PK,
            m.ZISFROMME,
            m.ZFROMJID,
            m.ZPUSHNAME,
            gm.ZCONTACTNAME AS group_member_contact_name,
            gm.ZFIRSTNAME AS group_member_first_name,
            gm.ZMEMBERJID AS group_member_jid,
            \(profilePushNameSelectSQL()) AS profile_push_name,
            m.ZTEXT,
            m.ZMESSAGEDATE,
            \(messageTypeSelectSQL()) AS message_type,
            \(groupEventTypeSelectSQL()) AS group_event_type,
            \(toJIDSelectSQL()) AS to_jid,
            c.ZCONTACTJID AS chat_contact_jid,
            \(statusStoryMessageSQL(messageAlias: "m", chatAlias: "c")) AS is_status_story,
            \(mediaSelectSQL())
        """
    }

    private func readMessages(from statement: OpaquePointer) throws -> [MessageRow] {
        var messages: [MessageRow] = []
        var stepResult = sqlite3_step(statement)
        while stepResult == SQLITE_ROW {
            let messageType = int(statement, 10)
            let groupEventType = int(statement, 11)
            let isStatusStory = sqlite3_column_int(statement, 14) != 0
            let media = mediaMetadata(
                from: statement,
                startingAt: 15,
                messageType: messageType,
                groupEventType: groupEventType,
                source: isStatusStory ? .statusStory : .normal
            )
            messages.append(
                MessageRow(
                    id: sqlite3_column_int64(statement, 0),
                    isFromMe: sqlite3_column_int(statement, 1) != 0,
                    senderJID: string(statement, 2),
                    pushName: string(statement, 3),
                    groupMemberContactName: string(statement, 4),
                    groupMemberFirstName: string(statement, 5),
                    groupMemberJID: string(statement, 6),
                    profilePushName: string(statement, 7),
                    contactsDisplayName: contactsResolver?.identity(for: string(statement, 6))?.displayName
                        ?? contactsResolver?.identity(for: string(statement, 2))?.displayName,
                    deviceContactsDisplayName: nil,
                    text: string(statement, 8),
                    messageDate: date(statement, 9),
                    messageType: messageType,
                    groupEventType: groupEventType,
                    isStatusStory: isStatusStory,
                    media: media
                )
            )
            stepResult = sqlite3_step(statement)
        }

        try throwIfStatementFailed(stepResult)
        return messages
    }

    private func validateSchema() throws {
        let requiredColumns: [String: Set<String>] = [
            "ZWACHATSESSION": [
                "Z_PK",
                "ZCONTACTJID",
                "ZCONTACTIDENTIFIER",
                "ZPARTNERNAME",
                "ZLASTMESSAGEDATE",
                "ZMESSAGECOUNTER"
            ],
            "ZWAMESSAGE": [
                "Z_PK",
                "ZCHATSESSION",
                "ZISFROMME",
                "ZFROMJID",
                "ZPUSHNAME",
                "ZTEXT",
                "ZMESSAGEDATE"
            ]
        ]

        for (table, required) in requiredColumns {
            guard try tableExists(table) else {
                throw WhatsAppDatabaseError.invalidSchema("missing table \(table)")
            }

            let actualColumns = try columns(in: table)
            let missingColumns = required.subtracting(actualColumns).sorted()
            if !missingColumns.isEmpty {
                throw WhatsAppDatabaseError.invalidSchema(
                    "\(table) missing columns \(missingColumns.joined(separator: ", "))"
                )
            }
        }
    }

    private func discoverMediaSchema() throws -> MediaSchema? {
        guard try tableExists("ZWAMEDIAITEM") else {
            return nil
        }
        return MediaSchema(columns: try columns(in: "ZWAMEDIAITEM"))
    }

    private func discoverProfilePushNameJoin() throws -> Bool {
        guard try tableExists("ZWAPROFILEPUSHNAME") else {
            return false
        }
        let columns = try columns(in: "ZWAPROFILEPUSHNAME")
        return columns.contains("ZJID") && columns.contains("ZPUSHNAME")
    }

    private func messageTypeSelectSQL() -> String {
        if messageColumns.contains("ZMESSAGETYPE") {
            return "m.ZMESSAGETYPE"
        }
        return "NULL"
    }

    private func groupEventTypeSelectSQL() -> String {
        if messageColumns.contains("ZGROUPEVENTTYPE") {
            return "m.ZGROUPEVENTTYPE"
        }
        return "NULL"
    }

    private func toJIDSelectSQL() -> String {
        if messageColumns.contains("ZTOJID") {
            return "m.ZTOJID"
        }
        return "NULL"
    }

    private func mediaSelectSQL() -> String {
        guard let mediaSchema, mediaSchema.canJoinMessages else {
            return [
                "NULL AS media_item_id",
                "NULL AS media_local_path",
                "NULL AS media_title",
                "NULL AS media_file_size",
                "NULL AS media_origin",
                "NULL AS media_url",
                "NULL AS media_vcard_name",
                "NULL AS media_vcard_string",
                "NULL AS media_latitude",
                "NULL AS media_longitude",
                "NULL AS media_duration"
            ].joined(separator: ",\n                    ")
        }

        return [
            mediaSchema.select("Z_PK", as: "media_item_id"),
            mediaSchema.select("ZMEDIALOCALPATH", as: "media_local_path"),
            mediaSchema.select("ZTITLE", as: "media_title"),
            mediaSchema.select("ZFILESIZE", as: "media_file_size"),
            mediaSchema.select("ZMEDIAORIGIN", as: "media_origin"),
            mediaSchema.select("ZMEDIAURL", as: "media_url"),
            mediaSchema.select("ZVCARDNAME", as: "media_vcard_name"),
            mediaSchema.select("ZVCARDSTRING", as: "media_vcard_string"),
            mediaSchema.select("ZLATITUDE", as: "media_latitude"),
            mediaSchema.select("ZLONGITUDE", as: "media_longitude"),
            mediaSchema.select("ZMOVIEDURATION", as: "media_duration")
        ].joined(separator: ",\n                    ")
    }

    private func mediaJoinSQL() -> String {
        guard mediaSchema?.canJoinMessages == true else {
            return ""
        }
        return "LEFT JOIN ZWAMEDIAITEM mi ON mi.ZMESSAGE = m.Z_PK"
    }

    private func mediaPresenceJoinSQL() -> String {
        guard shouldJoinMediaPresenceForChatSummary else {
            return ""
        }
        return """
            LEFT JOIN (
                SELECT DISTINCT ZMESSAGE
                FROM ZWAMEDIAITEM
                WHERE ZMESSAGE IS NOT NULL
            ) media_presence ON media_presence.ZMESSAGE = m.Z_PK
            """
    }

    private func chatSessionJoinSQL() -> String {
        "LEFT JOIN ZWACHATSESSION c ON c.Z_PK = m.ZCHATSESSION"
    }

    private func chatSessionJoinSQL(alias: String) -> String {
        "LEFT JOIN ZWACHATSESSION \(alias) ON \(alias).Z_PK = m.ZCHATSESSION"
    }

    private func groupMemberJoinSQL() -> String {
        let profileJoin = canJoinProfilePushNames
            ? "\n            LEFT JOIN ZWAPROFILEPUSHNAME pp ON pp.ZJID = gm.ZMEMBERJID"
            : ""
        return "LEFT JOIN ZWAGROUPMEMBER gm ON gm.Z_PK = m.ZGROUPMEMBER\(profileJoin)"
    }

    private func profilePushNameSelectSQL() -> String {
        canJoinProfilePushNames ? "pp.ZPUSHNAME" : "NULL"
    }

    private func mediaMetadata(
        from statement: OpaquePointer,
        startingAt index: Int32,
        messageType: Int?,
        groupEventType: Int?,
        source: MediaAttachmentSource
    ) -> MediaMetadata? {
        let itemID = int64(statement, index)
        let localPath = string(statement, index + 1)
        let title = string(statement, index + 2)
        let fileSize = int64(statement, index + 3)
        let mediaOrigin = int(statement, index + 4)
        let mediaURL = string(statement, index + 5)
        let vCardName = string(statement, index + 6)
        let vCardString = string(statement, index + 7)
        let latitude = double(statement, index + 8)
        let longitude = double(statement, index + 9)
        let durationSeconds = double(statement, index + 10)

        guard itemID != nil || localPath != nil || title != nil || fileSize != nil || mediaURL != nil || vCardName != nil || vCardString != nil || latitude != nil || longitude != nil || durationSeconds != nil else {
            return nil
        }

        let resolution = resolveMediaPath(localPath)
        let fileName = resolution.fileName ?? fileName(from: mediaURL) ?? title
        let mimeType = inferMimeType(fileName: fileName, localPath: localPath, mediaURL: mediaURL)
        let kind = inferMediaKind(
            input: MediaClassificationInput(
                messageType: messageType,
                groupEventType: groupEventType,
                localPath: localPath,
                title: title,
                mediaOrigin: mediaOrigin,
                mediaURL: mediaURL,
                vCardName: vCardName,
                vCardString: vCardString,
                latitude: latitude,
                longitude: longitude,
                durationSeconds: durationSeconds
            ),
            mimeType: mimeType,
            fileName: fileName
        )

        return MediaMetadata(
            itemID: itemID,
            localPath: resolution.relativePath ?? localPath,
            fileURL: resolution.fileURL,
            fileName: fileName,
            title: title,
            mediaURL: mediaURL,
            vCardName: vCardName,
            vCardString: vCardString,
            mimeType: mimeType,
            fileSize: fileSize,
            durationSeconds: durationSeconds,
            isFileAvailableInArchive: resolution.existsInArchive,
            isFileReadableInArchive: resolution.isReadable,
            kind: kind,
            source: source
        )
    }

    private func resolveMediaPath(_ localPath: String?) -> MediaPathResolution {
        guard let relativePath = normalizedRelativeMediaPath(from: localPath) else {
            return MediaPathResolution(relativePath: nil, fileURL: nil, fileName: nil, existsInArchive: false, isReadable: false)
        }

        let archiveRoot = archiveRootURL.standardizedFileURL
        let candidates = mediaPathCandidates(for: relativePath, in: archiveRoot)
        let candidate = candidates.first { candidate in
            isInsideArchive(candidate, archiveRoot: archiveRoot)
                && FileManager.default.fileExists(atPath: candidate.path)
        } ?? archiveRoot.appendingPathComponent(relativePath).standardizedFileURL
        let existsInArchive = isInsideArchive(candidate, archiveRoot: archiveRoot)
            && FileManager.default.fileExists(atPath: candidate.path)
        let isReadable = existsInArchive && FileManager.default.isReadableFile(atPath: candidate.path)

        return MediaPathResolution(
            relativePath: relativePath,
            fileURL: existsInArchive ? candidate : nil,
            fileName: candidate.lastPathComponent,
            existsInArchive: existsInArchive,
            isReadable: isReadable
        )
    }

    private func mediaPathCandidates(for relativePath: String, in archiveRoot: URL) -> [URL] {
        var candidatePaths = [relativePath]
        if relativePath.hasPrefix("Media/") {
            candidatePaths.append("Message/\(relativePath)")
        } else if relativePath.hasPrefix("Message/Media/") {
            candidatePaths.append(String(relativePath.dropFirst("Message/".count)))
        } else if !relativePath.hasPrefix("Message/") {
            candidatePaths.append("Media/\(relativePath)")
            candidatePaths.append("Message/\(relativePath)")
            candidatePaths.append("Message/Media/\(relativePath)")
        }

        var seen = Set<String>()
        return candidatePaths.compactMap { path in
            guard seen.insert(path).inserted else { return nil }
            return archiveRoot.appendingPathComponent(path).standardizedFileURL
        }
    }

    private func isInsideArchive(_ candidate: URL, archiveRoot: URL) -> Bool {
        let archiveRootPath = archiveRoot.path.hasSuffix("/") ? archiveRoot.path : archiveRoot.path + "/"
        return candidate.path.hasPrefix(archiveRootPath)
    }

    private func normalizedRelativeMediaPath(from value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        if let url = URL(string: value), url.isFileURL {
            value = url.path
        }

        let normalizedValue = value.replacingOccurrences(of: "\\", with: "/")
        var components = normalizedValue.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if let mediaIndex = components.firstIndex(where: { $0 == "Media" || $0 == "Message" }) {
            components = Array(components[mediaIndex...])
        }

        guard !components.isEmpty, !components.contains("..") else {
            return nil
        }

        return components.joined(separator: "/")
    }

    private func inferMimeType(fileName: String?, localPath: String?, mediaURL: String?) -> String? {
        guard let fileExtension = fileExtension(fileName: fileName, localPath: localPath, mediaURL: mediaURL) else {
            return nil
        }
        return UTType(filenameExtension: fileExtension)?.preferredMIMEType
    }

    private func inferMediaKind(
        input: MediaClassificationInput,
        mimeType: String?,
        fileName: String?
    ) -> MediaAttachmentKind {
        if input.messageType == 59 || input.messageType == 66 {
            return .call
        }
        if input.messageType == 10 || input.messageType == 6 {
            return .system
        }
        if input.messageType == 12 {
            return .deleted
        }
        if input.messageType == 4 {
            if hasVideoEvidence(input: input, mimeType: mimeType, fileName: fileName) {
                return .videoMessage
            }
            if hasReliableVCard(name: input.vCardName, string: input.vCardString, messageType: input.messageType) {
                return .contact
            }
            return .media
        }
        if input.messageType == 1 {
            return .photo
        }
        if input.messageType == 2 {
            return .video
        }
        if input.messageType == 3 {
            return isVoiceMessageAudio(input) ? .voiceMessage : .audio
        }
        if input.messageType == 5 {
            if hasVideoEvidence(input: input, mimeType: mimeType, fileName: fileName) {
                return .videoMessage
            }
            return hasPlausibleLocationEvidence(latitude: input.latitude, longitude: input.longitude) ? .location : .media
        }
        if input.messageType == 15 {
            return .sticker
        }
        if input.messageType == 7 {
            return .linkPreview
        }
        if input.messageType == 8 {
            return .document
        }
        if hasReliableVCard(name: input.vCardName, string: input.vCardString, messageType: input.messageType) {
            return .contact
        }
        if hasPlausibleLocationEvidence(latitude: input.latitude, longitude: input.longitude) {
            return .location
        }

        if let mimeType {
            if mimeType.hasPrefix("image/") {
                return .photo
            }
            if mimeType.hasPrefix("video/") {
                return .video
            }
            if mimeType.hasPrefix("audio/") {
                return isVoiceMessageAudio(input) ? .voiceMessage : .audio
            }
        }

        guard let fileExtension = fileExtension(fileName: fileName, localPath: input.localPath, mediaURL: input.mediaURL) else {
            if input.messageType == 0 {
                return .callOrSystem
            }
            return .media
        }

        switch fileExtension.lowercased() {
        case "jpg", "jpeg", "png", "gif", "heic", "webp":
            return input.messageType == 15 ? .sticker : .photo
        case "mp4", "mov", "m4v":
            return .video
        case "aac", "caf", "m4a", "mp3", "ogg", "opus", "wav":
            return isVoiceMessageAudio(input) ? .voiceMessage : .audio
        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "zip":
            return .document
        default:
            return input.messageType == 0 ? .callOrSystem : .media
        }
    }

    private func isVoiceMessageAudio(_ input: MediaClassificationInput) -> Bool {
        input.mediaOrigin == 1
    }

    private func hasReliableVCard(name: String?, string: String?, messageType: Int?) -> Bool {
        if let string = string?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty {
            let uppercasedString = string.uppercased()
            if uppercasedString.contains("BEGIN:VCARD")
                || uppercasedString.contains("END:VCARD")
                || uppercasedString.contains("\nFN:")
                || uppercasedString.hasPrefix("FN:")
                || uppercasedString.contains("\nTEL")
                || uppercasedString.hasPrefix("TEL") {
                return true
            }
        }

        guard messageType == 4 else { return false }
        return name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func hasVideoEvidence(
        input: MediaClassificationInput,
        mimeType: String?,
        fileName: String?
    ) -> Bool {
        if mimeType?.hasPrefix("video/") == true {
            return true
        }
        if let fileExtension = fileExtension(fileName: fileName, localPath: input.localPath, mediaURL: input.mediaURL)?.lowercased(),
           ["mp4", "mov", "m4v"].contains(fileExtension) {
            return true
        }
        return (input.messageType == 4 || input.messageType == 5) && (input.durationSeconds ?? 0) > 0
    }

    private func hasPlausibleLocationEvidence(
        latitude: Double?,
        longitude: Double?
    ) -> Bool {
        guard let latitude, let longitude else {
            return false
        }
        if latitude == 0 && longitude == 0 {
            return false
        }
        return abs(latitude) <= 90 && abs(longitude) <= 180
    }

    private func fileExtension(fileName: String?, localPath: String?, mediaURL: String?) -> String? {
        for value in [fileName, localPath, mediaURL] {
            guard let value, !value.isEmpty else { continue }
            let pathExtension = URL(fileURLWithPath: value).pathExtension
            if !pathExtension.isEmpty {
                return pathExtension
            }
        }
        return nil
    }

    private func fileName(from value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        let fileName = URL(fileURLWithPath: value).lastPathComponent
        return fileName.isEmpty ? nil : fileName
    }

    private func tableExists(_ table: String) throws -> Bool {
        let statement = try prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, table, -1, sqliteTransient)
        let result = sqlite3_step(statement)
        if result == SQLITE_ROW {
            return true
        }
        if result == SQLITE_DONE {
            return false
        }
        throw WhatsAppDatabaseError.queryFailed(lastErrorMessage)
    }

    private func columns(in table: String) throws -> Set<String> {
        let statement = try prepare("PRAGMA table_info(\(table))")
        defer { sqlite3_finalize(statement) }

        var columns = Set<String>()
        var stepResult = sqlite3_step(statement)
        while stepResult == SQLITE_ROW {
            if let column = string(statement, 1) {
                columns.insert(column)
            }
            stepResult = sqlite3_step(statement)
        }

        try throwIfStatementFailed(stepResult)
        return columns
    }

    private func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? lastErrorMessage
            sqlite3_free(errorMessage)
            throw WhatsAppDatabaseError.queryFailed(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw WhatsAppDatabaseError.queryFailed(lastErrorMessage)
        }
        return statement
    }

    private func throwIfStatementFailed(_ result: Int32) throws {
        guard result == SQLITE_DONE else {
            throw WhatsAppDatabaseError.queryFailed(String(cString: sqlite3_errmsg(database)))
        }
    }

    private var lastErrorMessage: String {
        guard let database else { return "database is not open" }
        return String(cString: sqlite3_errmsg(database))
    }

    private func string(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: text)
    }

    private func int(_ statement: OpaquePointer, _ index: Int32) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return Int(sqlite3_column_int(statement, index))
    }

    private func int64(_ statement: OpaquePointer, _ index: Int32) -> Int64? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return sqlite3_column_int64(statement, index)
    }

    private func double(_ statement: OpaquePointer, _ index: Int32) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return sqlite3_column_double(statement, index)
    }

    private func date(_ statement: OpaquePointer, _ index: Int32) -> Date? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, index))
    }
}
