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
    let fileName: String?
    let existsInArchive: Bool
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
    let contactJID: String?
    let contactIdentifier: String?
    let partnerName: String?
    let title: String
    let messageCount: Int
    let latestMessageDate: Date?
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
        let latestRelevantMessageDateSQL: String
        if messageColumns.contains("ZMESSAGETYPE") {
            latestRelevantMessageDateSQL = """
                CASE
                    WHEN COALESCE(m.ZMESSAGETYPE, -1) NOT IN (6, 10)
                    THEN m.ZMESSAGEDATE
                    ELSE NULL
                END
                """
        } else {
            latestRelevantMessageDateSQL = "m.ZMESSAGEDATE"
        }

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
                MAX(\(latestRelevantMessageDateSQL)) AS latest_relevant_message_date,
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
            ORDER BY COALESCE(latest_relevant_message_date, last_message_pointer_date, latest_any_message_date, sanitized_last_message_date, 0) DESC, c.Z_PK ASC
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
            let title = DisplayNameSanitizer.friendlyName(partnerName)
                ?? DisplayNameSanitizer.friendlyName(contactIdentifier)
                ?? (isGroupJID(contactJID) ? "Group chat" : "Unknown chat")
            let latestMessageDate = date(statement, 8) ?? date(statement, 10) ?? date(statement, 9) ?? date(statement, 6)

            rows.append(
                ChatSummaryRow(
                    id: id,
                    contactJID: contactJID,
                    contactIdentifier: contactIdentifier,
                    partnerName: partnerName,
                    title: title,
                    messageCount: Int(sqlite3_column_int64(statement, 7)),
                    latestMessageDate: latestMessageDate
                )
            )
            stepResult = sqlite3_step(statement)
        }

        try throwIfStatementFailed(stepResult)
        return mergedChatSummaries(from: rows)
    }

    private func isGroupJID(_ value: String?) -> Bool {
        value?.contains("@g.us") == true
    }

    func fetchMessages(sessionIDs: [Int64], limit: Int = 500) throws -> [MessageRow] {
        let sessionIDs = normalizedSessionIDs(sessionIDs)
        let placeholders = sessionPlaceholders(for: sessionIDs)
        let sql = """
            SELECT *
            FROM (
                \(messageRowSelectSQL())
                FROM ZWAMESSAGE m
                \(mediaJoinSQL())
                \(groupMemberJoinSQL())
                WHERE m.ZCHATSESSION IN (\(placeholders))
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
        limit: Int = 500
    ) throws -> [MessageRow] {
        let sessionIDs = normalizedSessionIDs(sessionIDs)
        let placeholders = sessionPlaceholders(for: sessionIDs)
        let sql = """
            \(messageRowSelectSQL())
            FROM ZWAMESSAGE m
            \(mediaJoinSQL())
            \(groupMemberJoinSQL())
            WHERE m.ZCHATSESSION IN (\(placeholders))
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

    private func mergedChatSummaries(from rows: [ChatSummaryRow]) -> [ChatSummary] {
        let groupedRows = Dictionary(grouping: rows) { row -> String in
            if let contactJID = row.contactJID?.trimmingCharacters(in: .whitespacesAndNewlines), !contactJID.isEmpty {
                return "jid:\(contactJID)"
            }
            return "session:\(row.id)"
        }

        var summaries = groupedRows.values.map { group -> ChatSummary in
            let sortedGroup = group.sorted { lhs, rhs in
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
            let primary = sortedGroup[0]
            let sessionIDs = sortedGroup.map(\.id).sorted()
            let messageCount = sortedGroup.reduce(0) { $0 + $1.messageCount }
            let latestMessageDate = sortedGroup.compactMap(\.latestMessageDate).max()
            let detailText = sessionIDs.count > 1
                ? "\(sessionIDs.count) archive sessions, \(messageCount.formatted()) messages"
                : "\(messageCount.formatted()) messages"

            return ChatSummary(
                id: primary.id,
                sessionIDs: sessionIDs,
                contactJID: primary.contactJID,
                contactIdentifier: primary.contactIdentifier,
                partnerName: primary.partnerName,
                title: primary.title,
                detailText: detailText,
                messageCount: messageCount,
                latestMessageDate: latestMessageDate,
                searchableTitle: primary.title
            )
        }

        let duplicateTitleCounts = Dictionary(grouping: summaries, by: \.title)
            .mapValues(\.count)

        var duplicateTitleIndexes: [String: Int] = [:]
        summaries = summaries.sorted(by: chatSummarySort).map { summary in
            let duplicateCount = duplicateTitleCounts[summary.title, default: 0]
            guard duplicateCount > 1 else {
                return summary
            }
            let duplicateIndex = duplicateTitleIndexes[summary.title, default: 0] + 1
            duplicateTitleIndexes[summary.title] = duplicateIndex
            return ChatSummary(
                id: summary.id,
                sessionIDs: summary.sessionIDs,
                contactJID: summary.contactJID,
                contactIdentifier: summary.contactIdentifier,
                partnerName: summary.partnerName,
                title: summary.title,
                detailText: "Archive session \(duplicateIndex) of \(duplicateCount), \(summary.detailText)",
                messageCount: summary.messageCount,
                latestMessageDate: summary.latestMessageDate,
                searchableTitle: summary.searchableTitle
            )
        }

        return summaries.sorted(by: chatSummarySort)
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
            \(mediaSelectSQL())
        """
    }

    private func readMessages(from statement: OpaquePointer) throws -> [MessageRow] {
        var messages: [MessageRow] = []
        var stepResult = sqlite3_step(statement)
        while stepResult == SQLITE_ROW {
            let messageType = int(statement, 10)
            let groupEventType = int(statement, 11)
            let media = mediaMetadata(
                from: statement,
                startingAt: 12,
                messageType: messageType,
                groupEventType: groupEventType
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
                    text: string(statement, 8),
                    messageDate: date(statement, 9),
                    messageType: messageType,
                    groupEventType: groupEventType,
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
                "NULL AS media_longitude"
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
            mediaSchema.select("ZLONGITUDE", as: "media_longitude")
        ].joined(separator: ",\n                    ")
    }

    private func mediaJoinSQL() -> String {
        guard mediaSchema?.canJoinMessages == true else {
            return ""
        }
        return "LEFT JOIN ZWAMEDIAITEM mi ON mi.ZMESSAGE = m.Z_PK"
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
        groupEventType: Int?
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

        guard itemID != nil || localPath != nil || title != nil || fileSize != nil || mediaURL != nil || vCardName != nil || vCardString != nil || latitude != nil || longitude != nil else {
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
            fileName: fileName,
            title: title,
            mimeType: mimeType,
            fileSize: fileSize,
            isFileAvailableInArchive: resolution.existsInArchive,
            kind: kind
        )
    }

    private func resolveMediaPath(_ localPath: String?) -> MediaPathResolution {
        guard let relativePath = normalizedRelativeMediaPath(from: localPath) else {
            return MediaPathResolution(relativePath: nil, fileName: nil, existsInArchive: false)
        }

        let archiveRoot = archiveRootURL.standardizedFileURL
        let candidates = mediaPathCandidates(for: relativePath, in: archiveRoot)
        let candidate = candidates.first { candidate in
            isInsideArchive(candidate, archiveRoot: archiveRoot)
                && FileManager.default.fileExists(atPath: candidate.path)
        } ?? archiveRoot.appendingPathComponent(relativePath).standardizedFileURL

        return MediaPathResolution(
            relativePath: relativePath,
            fileName: candidate.lastPathComponent,
            existsInArchive: isInsideArchive(candidate, archiveRoot: archiveRoot)
                && FileManager.default.fileExists(atPath: candidate.path)
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
