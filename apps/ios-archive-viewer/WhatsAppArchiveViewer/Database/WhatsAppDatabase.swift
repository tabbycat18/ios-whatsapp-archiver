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
    let mediaURL: String?
    let vCardName: String?
    let vCardString: String?
    let latitude: Double?
    let longitude: Double?
}

private struct ChatSummaryRow {
    let id: Int64
    let identityKey: String
    let contactJID: String?
    let contactIdentifier: String?
    let partnerName: String?
    let title: String
    let messageCount: Int
    let userVisibleMessageCount: Int
    let systemMessageCount: Int
    let statusStoryMessageCount: Int
    let latestUserVisibleMessageDate: Date?
    let latestAnyMessageDate: Date?
    let fallbackMessageDate: Date?
}

private struct ContactIdentity {
    let key: String
    let displayName: String?
}

private struct ChatActivityMetrics {
    let messageCount: Int
    let userVisibleMessageCount: Int
    let systemMessageCount: Int
    let statusStoryMessageCount: Int

    var hasUserVisibleMessages: Bool {
        userVisibleMessageCount > 0
    }

    var hasOnlyStatusStoryMessages: Bool {
        messageCount > 0 && statusStoryMessageCount == messageCount
    }
}

private struct ChatSummaryDraft {
    let id: Int64
    let sessionIDs: [Int64]
    let contactJID: String?
    let contactIdentifier: String?
    let partnerName: String?
    let title: String
    let detailText: String
    let latestUserVisibleMessageDate: Date?
    let latestAnyMessageDate: Date?
    let fallbackMessageDate: Date?
    let searchableTitle: String
    let activity: ChatActivityMetrics
}

private final class ContactsV2Resolver {
    private var database: OpaquePointer?
    private var identitiesByJID: [String: ContactIdentity] = [:]

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
            try loadContacts()
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

    private func loadContacts() throws {
        guard try tableExists("ZWAADDRESSBOOKCONTACT") else { return }
        let columns = try columns(in: "ZWAADDRESSBOOKCONTACT")
        guard columns.contains("Z_PK") else { return }

        let sql = """
            SELECT
                Z_PK,
                \(select("ZWHATSAPPID", columns: columns)),
                \(select("ZLID", columns: columns)),
                \(select("ZFULLNAME", columns: columns)),
                \(select("ZGIVENNAME", columns: columns)),
                \(select("ZLASTNAME", columns: columns)),
                \(select("ZBUSINESSNAME", columns: columns)),
                \(select("ZHIGHLIGHTEDNAME", columns: columns)),
                \(select("ZUSERNAME", columns: columns))
            FROM ZWAADDRESSBOOKCONTACT
            """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        var candidatesByJID: [String: [ContactIdentity]] = [:]
        var stepResult = sqlite3_step(statement)
        while stepResult == SQLITE_ROW {
            let identity = ContactIdentity(
                key: "contactsV2:\(sqlite3_column_int64(statement, 0))",
                displayName: displayName(
                    fullName: string(statement, 3),
                    givenName: string(statement, 4),
                    lastName: string(statement, 5),
                    businessName: string(statement, 6),
                    highlightedName: string(statement, 7),
                    username: string(statement, 8)
                )
            )

            for jid in [string(statement, 1), string(statement, 2)].compactMap(normalizedJID) {
                candidatesByJID[jid, default: []].append(identity)
            }
            stepResult = sqlite3_step(statement)
        }
        try throwIfStatementFailed(stepResult)

        identitiesByJID = candidatesByJID.compactMapValues { identities in
            let keys = Set(identities.map(\.key))
            guard keys.count == 1 else { return nil }
            return identities[0]
        }
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

final class WhatsAppDatabase {
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
            try validateSchema()
            messageColumns = try columns(in: "ZWAMESSAGE")
            mediaSchema = try discoverMediaSchema()
            canJoinProfilePushNames = try discoverProfilePushNameJoin()
            contactsResolver = ContactsV2Resolver(archiveRootURL: self.archiveRootURL)
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
        let userVisibleMessageSQL = userVisibleMessageSQL(messageAlias: "m", chatAlias: "c")
        let mediaEvidenceSQL = mediaEvidenceSQL(alias: "m")
        let systemMessageSQL = systemMessageSQL(alias: "m")
        let statusStoryMessageSQL = statusStoryMessageSQL(messageAlias: "m", chatAlias: "c")

        let sql = """
            SELECT
                c.Z_PK,
                c.ZCONTACTJID,
                c.ZCONTACTIDENTIFIER,
                c.ZPARTNERNAME,
                c.ZLASTMESSAGEDATE,
                c.ZMESSAGECOUNTER,
                CASE
                    WHEN c.ZLASTMESSAGEDATE BETWEEN 0 AND 1500000000
                    THEN c.ZLASTMESSAGEDATE
                    ELSE NULL
                END AS sanitized_last_message_date,
                COUNT(m.Z_PK) AS message_count,
                SUM(CASE WHEN \(userVisibleMessageSQL) THEN 1 ELSE 0 END) AS user_visible_message_count,
                SUM(CASE WHEN \(textMessageSQL(alias: "m")) THEN 1 ELSE 0 END) AS text_message_count,
                SUM(CASE WHEN \(mediaEvidenceSQL) THEN 1 ELSE 0 END) AS media_message_count,
                SUM(CASE WHEN \(callMessageSQL(alias: "m")) THEN 1 ELSE 0 END) AS call_message_count,
                SUM(CASE WHEN \(systemMessageSQL) THEN 1 ELSE 0 END) AS system_message_count,
                SUM(CASE WHEN \(statusStoryMessageSQL) THEN 1 ELSE 0 END) AS status_story_message_count,
                MAX(CASE WHEN \(userVisibleMessageSQL) THEN m.ZMESSAGEDATE ELSE NULL END) AS latest_user_visible_message_date,
                MAX(m.ZMESSAGEDATE) AS latest_any_message_date,
                lm.ZMESSAGEDATE AS last_message_pointer_date
            FROM ZWACHATSESSION c
            LEFT JOIN ZWAMESSAGE m ON m.ZCHATSESSION = c.Z_PK
            LEFT JOIN ZWAMESSAGE lm ON lm.Z_PK = c.ZLASTMESSAGE
            GROUP BY
                c.Z_PK,
                c.ZCONTACTJID,
                c.ZCONTACTIDENTIFIER,
                c.ZPARTNERNAME,
                c.ZLASTMESSAGEDATE,
                c.ZMESSAGECOUNTER,
                lm.ZMESSAGEDATE
            ORDER BY COALESCE(latest_user_visible_message_date, last_message_pointer_date, latest_any_message_date, sanitized_last_message_date, 0) DESC, c.Z_PK ASC
            """

        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        var rows: [ChatSummaryRow] = []
        var stepResult = sqlite3_step(statement)
        while stepResult == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let contactJID = string(statement, 1)
            let contactIdentifier = string(statement, 2)
            let partnerName = string(statement, 3)
            let contactIdentity = contactsResolver?.identity(for: contactJID)
            let title = DisplayNameSanitizer.friendlyName(contactIdentity?.displayName)
                ?? DisplayNameSanitizer.friendlyName(partnerName)
                ?? DisplayNameSanitizer.friendlyName(contactIdentifier)
                ?? (isGroupJID(contactJID) ? "Group chat" : "Unknown chat")
            let messageCount = Int(sqlite3_column_int64(statement, 7))
            let statusStoryMessageCount = Int(sqlite3_column_int64(statement, 13))
            let latestUserVisibleMessageDate = date(statement, 14)
            let latestAnyMessageDate = date(statement, 15)
            let fallbackMessageDate = latestUserVisibleMessageDate ?? date(statement, 16) ?? latestAnyMessageDate ?? date(statement, 6)

            rows.append(
                ChatSummaryRow(
                    id: id,
                    identityKey: statusStoryMessageCount == messageCount && messageCount > 0
                        ? "status-stories"
                        : chatIdentityKey(id: id, contactJID: contactJID, contactIdentity: contactIdentity),
                    contactJID: contactJID,
                    contactIdentifier: contactIdentifier,
                    partnerName: partnerName,
                    title: title,
                    messageCount: messageCount,
                    userVisibleMessageCount: Int(sqlite3_column_int64(statement, 8)),
                    systemMessageCount: Int(sqlite3_column_int64(statement, 12)),
                    statusStoryMessageCount: statusStoryMessageCount,
                    latestUserVisibleMessageDate: latestUserVisibleMessageDate,
                    latestAnyMessageDate: latestAnyMessageDate,
                    fallbackMessageDate: fallbackMessageDate
                )
            )
            stepResult = sqlite3_step(statement)
        }

        try throwIfStatementFailed(stepResult)
        return mergedChatSummaries(from: rows)
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
        return """
        (m.ZMESSAGETYPE = 2
        OR \(path) LIKE '%.mp4'
        OR \(path) LIKE '%.mov'
        OR \(path) LIKE '%.m4v')
        """
    }

    private func audioMediaSQL() -> String {
        let path = "lower(COALESCE(mi.ZMEDIALOCALPATH, mi.ZMEDIAURL, mi.ZTITLE, ''))"
        return """
        (m.ZMESSAGETYPE = 3
        OR \(path) LIKE '%.aac'
        OR \(path) LIKE '%.caf'
        OR \(path) LIKE '%.m4a'
        OR \(path) LIKE '%.mp3'
        OR \(path) LIKE '%.ogg'
        OR \(path) LIKE '%.opus'
        OR \(path) LIKE '%.wav')
        """
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
        "(\(photoMediaSQL()) OR \(videoMediaSQL()) OR \(audioMediaSQL()) OR \(documentMediaSQL()))"
    }

    private func callMessageSQL(alias: String) -> String {
        guard messageColumns.contains("ZMESSAGETYPE") else {
            return "0"
        }
        return "(\(alias).ZMESSAGETYPE IN (59, 66))"
    }

    private func systemMessageSQL(alias: String) -> String {
        guard messageColumns.contains("ZMESSAGETYPE") else {
            return "0"
        }
        return "(\(alias).ZMESSAGETYPE IN (6, 10))"
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
        let statusStoryFilterSQL = includeStatusStoryMessages
            ? "1"
            : "NOT \(statusStoryMessageSQL(messageAlias: "m", chatAlias: "c"))"
        let sql = """
            SELECT *
            FROM (
                \(messageRowSelectSQL())
                FROM ZWAMESSAGE m
                \(chatSessionJoinSQL())
                \(mediaJoinSQL())
                \(groupMemberJoinSQL())
                WHERE m.ZCHATSESSION IN (\(placeholders))
                  AND \(statusStoryFilterSQL)
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
        let statusStoryFilterSQL = includeStatusStoryMessages
            ? "1"
            : "NOT \(statusStoryMessageSQL(messageAlias: "m", chatAlias: "c"))"
        let sql = """
            \(messageRowSelectSQL())
            FROM ZWAMESSAGE m
            \(chatSessionJoinSQL())
            \(mediaJoinSQL())
            \(groupMemberJoinSQL())
            WHERE m.ZCHATSESSION IN (\(placeholders))
              AND \(statusStoryFilterSQL)
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
        includeStatusStoriesInAll: Bool,
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
            filterSQL = includeStatusStoriesInAll
                ? candidateSQL
                : "NOT \(statusStorySQL) AND \(candidateSQL)"
        case .photos:
            filterSQL = "NOT \(statusStorySQL) AND \(photoMediaSQL())"
        case .videos:
            filterSQL = "NOT \(statusStorySQL) AND \(videoMediaSQL())"
        case .statusStories:
            filterSQL = "\(statusStorySQL) AND \(candidateSQL)"
        }

        let totalRowsMatchingFilter = try countMediaRows(
            sessionIDs: sessionIDs,
            placeholders: placeholders,
            filterSQL: filterSQL
        )
        let statusStoryRowsExcluded = filter == .statusStories
            ? 0
            : try countMediaRows(
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

            guard shouldIncludeInMediaLibrary(media, filter: filter, includeStatusStoriesInAll: includeStatusStoriesInAll) else {
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
        filter: ChatMediaFilter,
        includeStatusStoriesInAll: Bool
    ) -> Bool {
        switch filter {
        case .all:
            guard includeStatusStoriesInAll || media.source != .statusStory else {
                return false
            }
            return isMediaLibraryDisplayable(media.kind)
        case .photos:
            return media.source != .statusStory && media.kind == .photo
        case .videos:
            return media.source != .statusStory && media.kind == .video
        case .statusStories:
            return media.source == .statusStory && isMediaLibraryDisplayable(media.kind)
        }
    }

    private func isMediaLibraryDisplayable(_ kind: MediaAttachmentKind) -> Bool {
        switch kind {
        case .photo, .video, .audio, .sticker, .document:
            return true
        case .contact, .location, .linkPreview, .call, .callOrSystem, .system, .deleted, .media:
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
            videoRows: displayedItems.filter { $0.media.kind == .video }.count,
            audioRows: displayedItems.filter { $0.media.kind == .audio }.count,
            otherRows: displayedItems.filter { item in
                item.media.kind != .photo
                    && item.media.kind != .sticker
                    && item.media.kind != .video
                    && item.media.kind != .audio
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
                partnerName: primary.partnerName,
                title: statusStoryMessageCount == messageCount && messageCount > 0 ? "Stories / Status" : primary.title,
                detailText: detailText,
                latestUserVisibleMessageDate: latestUserVisibleMessageDate,
                latestAnyMessageDate: latestAnyMessageDate,
                fallbackMessageDate: fallbackMessageDate,
                searchableTitle: statusStoryMessageCount == messageCount && messageCount > 0 ? "Stories Status" : primary.title,
                activity: ChatActivityMetrics(
                    messageCount: messageCount,
                    userVisibleMessageCount: userVisibleMessageCount,
                    systemMessageCount: systemMessageCount,
                    statusStoryMessageCount: statusStoryMessageCount
                )
            )
        }

        let visibleDrafts = drafts.filter { draft in
            !isHiddenFromDefaultChatList(baseClassification(for: draft.activity))
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
                partnerName: draft.partnerName,
                title: draft.title,
                detailText: detailText(for: draft, classification: classification),
                messageCount: draft.activity.messageCount,
                latestMessageDate: latestDisplayDate(for: draft, classification: classification),
                searchableTitle: draft.searchableTitle,
                classification: classification
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
        if activity.messageCount > 0, activity.systemMessageCount == activity.messageCount {
            return .systemOnlyFragment
        }
        if activity.messageCount <= 5 {
            return .archiveFragment
        }
        return .unknown
    }

    private func isHiddenFromDefaultChatList(_ classification: ChatSessionClassification) -> Bool {
        switch classification {
        case .archiveFragment, .systemOnlyFragment:
            return true
        case .normalConversation, .separateConversation, .statusStoryFragment, .unknown:
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
            return "Status/story media, \(draft.detailText)"
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
            return draft.latestUserVisibleMessageDate ?? draft.fallbackMessageDate
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
                    contactsDisplayName: contactsResolver?.identity(for: string(statement, 6))?.displayName,
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

    private func chatSessionJoinSQL() -> String {
        "LEFT JOIN ZWACHATSESSION c ON c.Z_PK = m.ZCHATSESSION"
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
        let mediaURL = string(statement, index + 4)
        let vCardName = string(statement, index + 5)
        let vCardString = string(statement, index + 6)
        let latitude = double(statement, index + 7)
        let longitude = double(statement, index + 8)
        let durationSeconds = double(statement, index + 9)

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
                mediaURL: mediaURL,
                vCardName: vCardName,
                vCardString: vCardString,
                latitude: latitude,
                longitude: longitude
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
        if input.messageType == 1 {
            return .photo
        }
        if input.messageType == 2 {
            return .video
        }
        if input.messageType == 3 {
            return .audio
        }
        if input.messageType == 4 {
            return .contact
        }
        if input.messageType == 5 {
            return .location
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
        if hasVCard(name: input.vCardName, string: input.vCardString) {
            return .contact
        }
        if hasNonzeroLocation(latitude: input.latitude, longitude: input.longitude) {
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
                return .audio
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
            return .audio
        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "zip":
            return .document
        default:
            return input.messageType == 0 ? .callOrSystem : .media
        }
    }

    private func hasVCard(name: String?, string: String?) -> Bool {
        [name, string].contains { value in
            value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    private func hasNonzeroLocation(latitude: Double?, longitude: Double?) -> Bool {
        guard let latitude, let longitude else {
            return false
        }
        return latitude != 0 || longitude != 0
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
