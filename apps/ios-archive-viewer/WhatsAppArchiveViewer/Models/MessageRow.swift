import Foundation

enum MediaAttachmentKind: String, Hashable, Sendable {
    case photo
    case video
    case videoMessage
    case audio
    case voiceMessage
    case contact
    case location
    case sticker
    case document
    case linkPreview
    case call
    case callOrSystem
    case system
    case deleted
    case media

    var placeholderText: String {
        switch self {
        case .photo:
            return "Photo attachment"
        case .video:
            return "Video attachment"
        case .videoMessage:
            return "Video message"
        case .audio:
            return "Audio attachment"
        case .voiceMessage:
            return "Voice message"
        case .contact:
            return "Contact card"
        case .location:
            return "Location"
        case .sticker:
            return "Sticker"
        case .document:
            return "Document attachment"
        case .linkPreview:
            return "Link preview"
        case .call:
            return "Voice call"
        case .callOrSystem:
            return "Call or system message"
        case .system:
            return "System message"
        case .deleted:
            return "Deleted message"
        case .media:
            return "Media attachment"
        }
    }
}

enum MediaAttachmentSource: String, Hashable, Sendable {
    case normal
    case statusStory
}

struct MediaMetadata: Hashable, Sendable {
    let itemID: Int64?
    let localPath: String?
    let fileURL: URL?
    let fileName: String?
    let title: String?
    let mediaURL: String?
    let vCardName: String?
    let vCardString: String?
    let mimeType: String?
    let fileSize: Int64?
    let durationSeconds: Double?
    let isFileAvailableInArchive: Bool
    let isFileReadableInArchive: Bool
    let kind: MediaAttachmentKind
    let source: MediaAttachmentSource

    var contactDisplayName: String? {
        DisplayNameSanitizer.friendlyName(vCardName)
            ?? DisplayNameSanitizer.friendlyName(title)
            ?? Self.vCardField(named: "FN", in: vCardString)
            ?? Self.vCardNameComponents(in: vCardString)
    }

    var linkPreviewURL: URL? {
        Self.normalizedWebURL(from: mediaURL)
            ?? Self.normalizedWebURL(from: title)
    }

    var documentDisplayTitle: String {
        DisplayNameSanitizer.friendlyName(title)
            ?? DisplayNameSanitizer.friendlyName(fileName)
            ?? "Document"
    }

    var fileExtensionLabel: String? {
        Self.fileExtension(from: fileName)
            ?? Self.fileExtension(from: localPath)
            ?? Self.fileExtension(from: mediaURL)
            ?? Self.fileExtension(from: title)
    }

    var documentTypeLabel: String {
        fileExtensionLabel?.uppercased()
            ?? mimeType
            ?? "File"
    }

    var fallbackCaptionText: String? {
        switch kind {
        case .photo, .video, .videoMessage, .audio, .voiceMessage:
            return Self.safeCaptionText(title)
        case .contact, .location, .sticker, .document, .linkPreview, .call, .callOrSystem, .system, .deleted, .media:
            return nil
        }
    }

    var searchableAttachmentLabels: [String] {
        switch kind {
        case .document:
            return [
                "Document",
                documentDisplayTitle,
                fileExtensionLabel
            ].compactMap { $0 }
        default:
            return [kind.placeholderText, fallbackCaptionText].compactMap { $0 }
        }
    }

    static func normalizedWebURL(from value: String?) -> URL? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        let candidate = value.contains("://") ? value : "https://\(value)"
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }

    private static func fileExtension(from value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        let fileExtension = URL(fileURLWithPath: value).pathExtension
        return fileExtension.isEmpty ? nil : fileExtension.lowercased()
    }

    private static func safeCaptionText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        guard normalizedWebURL(from: trimmed) == nil,
              !looksLikeFileOrPath(trimmed),
              !DisplayNameSanitizer.isRawIdentifierLike(trimmed) else {
            return nil
        }
        return trimmed
    }

    private static func looksLikeFileOrPath(_ value: String) -> Bool {
        if value.contains("/") || value.contains("\\") {
            return true
        }

        let fileExtensions = [
            "jpg", "jpeg", "png", "heic", "webp", "gif",
            "mp4", "mov", "m4v",
            "aac", "caf", "m4a", "mp3", "ogg", "opus", "wav",
            "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "zip"
        ]
        let lowercased = value.lowercased()
        return fileExtensions.contains { lowercased.hasSuffix(".\($0)") }
    }

    private static func vCardField(named fieldName: String, in vCardString: String?) -> String? {
        guard let vCardString else { return nil }
        return vCardString
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { return nil }
                let key = parts[0].split(separator: ";", maxSplits: 1).first?.uppercased()
                guard key == fieldName else { return nil }
                let value = parts[1].replacingOccurrences(of: "\\;", with: ";")
                return DisplayNameSanitizer.friendlyName(value)
            }
            .first
    }

    private static func vCardNameComponents(in vCardString: String?) -> String? {
        guard let rawName = vCardField(named: "N", in: vCardString) else { return nil }
        let components = rawName
            .split(separator: ";")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let displayName = components.reversed().joined(separator: " ")
        return DisplayNameSanitizer.friendlyName(displayName)
    }
}

struct MessageRow: Identifiable, Hashable, Sendable {
    let id: Int64
    let isFromMe: Bool
    let senderJID: String?
    let pushName: String?
    let groupMemberContactName: String?
    let groupMemberFirstName: String?
    let groupMemberJID: String?
    let profilePushName: String?
    let contactsDisplayName: String?
    let deviceContactsDisplayName: String?
    let text: String?
    let messageDate: Date?
    let messageType: Int?
    let groupEventType: Int?
    let isStatusStory: Bool
    let media: MediaMetadata?

    var paginationCursor: MessagePaginationCursor? {
        guard let messageDate else { return nil }
        return MessagePaginationCursor(messageDate: messageDate, messageID: id)
    }

    var friendlySenderName: String? {
        DisplayNameSanitizer.friendlyName(groupMemberContactName)
            ?? DisplayNameSanitizer.friendlyName(groupMemberFirstName)
            ?? DisplayNameSanitizer.friendlyName(pushName)
            ?? DisplayNameSanitizer.friendlyName(profilePushName)
            ?? DisplayNameSanitizer.friendlyName(contactsDisplayName)
            ?? DisplayNameSanitizer.friendlyName(deviceContactsDisplayName)
    }

    var senderDisplayName: String? {
        friendlySenderName
    }

    var senderProfilePhotoJID: String? {
        let groupMember = groupMemberJID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let groupMember, !groupMember.isEmpty {
            return groupMember
        }

        let sender = senderJID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let sender, !sender.isEmpty {
            return sender
        }

        return nil
    }

    var senderProfilePhotoIdentifier: String? {
        safeSenderPhoneNumber
    }

    var senderAvatarGroupingKey: String {
        if let senderProfilePhotoJID {
            return senderProfilePhotoJID
        }

        if let senderProfilePhotoIdentifier {
            return senderProfilePhotoIdentifier
        }

        if let senderDisplayName {
            return senderDisplayName
        }

        return "unknown sender"
    }

    var senderInitials: String? {
        guard let senderDisplayName else { return nil }
        return Self.senderInitials(from: senderDisplayName)
    }

    var safeSenderPhoneNumber: String? {
        PhoneNumberNormalizer.safeDisplayPhoneNumber(from: groupMemberJID)
            ?? PhoneNumberNormalizer.safeDisplayPhoneNumber(from: senderJID)
    }

    var displayText: String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        guard !shouldSuppressRawSystemText(trimmed) else {
            return nil
        }
        return trimmed
    }

    var mediaCaptionText: String? {
        guard media != nil else { return nil }
        return displayText
    }

    var nonTextPlaceholderText: String? {
        if let media {
            return media.kind.placeholderText
        }
        if Self.isCallMessageType(messageType) {
            return MediaAttachmentKind.call.placeholderText
        }
        if Self.isSystemMessageType(messageType) {
            return MediaAttachmentKind.system.placeholderText
        }
        if messageType == 12 {
            return MediaAttachmentKind.deleted.placeholderText
        }
        return nil
    }

    var isVoiceCallEvent: Bool {
        media?.kind == .call || Self.isCallMessageType(messageType)
    }

    private static func senderInitials(from value: String?) -> String? {
        guard let value else { return nil }
        let sanitized = DisplayNameSanitizer.friendlyName(value) ?? value

        let chunks = sanitized
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "+" })
            .compactMap { chunk -> String? in
                let normalized = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else { return nil }
                for scalar in normalized.unicodeScalars {
                    if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
                        return String(scalar)
                            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                            .uppercased()
                    }
                }
                return nil
            }

        if let chunkInitial = chunks.first, chunks.count == 1 {
            return chunkInitial
        }

        let combined = chunks.prefix(2).joined()
        return combined.isEmpty ? nil : String(combined)
    }

    private static func isSystemMessageType(_ value: Int?) -> Bool {
        value == 6 || value == 10
    }

    private static func isCallMessageType(_ value: Int?) -> Bool {
        value == 59 || value == 66
    }

    private func shouldSuppressRawSystemText(_ value: String) -> Bool {
        guard Self.isSystemMessageType(messageType) || media?.kind == .system else {
            return false
        }
        let lowercased = value.lowercased()
        guard lowercased.contains("@lid")
            || lowercased.contains("@s.whatsapp.net")
            || lowercased.contains("@g.us")
            || value.contains(";")
            || value.contains(",") else {
            return false
        }
        return true
    }
}

enum ChatMediaFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case photos
    case videos
    case documents

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .photos:
            return "Photos"
        case .videos:
            return "Videos"
        case .documents:
            return "Docs"
        }
    }
}

struct ChatMediaItem: Identifiable, Hashable, Sendable {
    let id: String
    let messageID: Int64
    let messageDate: Date?
    let media: MediaMetadata
}

struct ChatMediaLoadSummary: Hashable, Sendable {
    let totalRowsMatchingFilter: Int
    let rowsScanned: Int
    let displayedRows: Int
    let rowsWithLocalPath: Int
    let photoRows: Int
    let videoRows: Int
    let audioRows: Int
    let otherRows: Int
    let resolvedFileURLRows: Int
    let existingFileRows: Int
    let readableFileRows: Int
    let missingOrUnresolvedRows: Int
    let statusStoryRowsExcluded: Int
    let queryCapMayHideRows: Bool
}

struct ChatMediaLibraryPage: Hashable, Sendable {
    let items: [ChatMediaItem]
    let summary: ChatMediaLoadSummary
}

struct MessagePaginationCursor: Hashable, Sendable {
    let messageDate: Date
    let messageID: Int64
}

enum DisplayNameSanitizer {
    static func friendlyName(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        guard !isRawIdentifierLike(trimmed) else {
            return nil
        }
        return trimmed
    }

    static func isRawIdentifierLike(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        if trimmed.range(of: #"@[A-Za-z0-9.-]*whatsapp\.net|@g\.us|@s\.whatsapp\.net"#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.contains("@") {
            return true
        }
        if trimmed.range(of: #"^[+0-9 ()-]{6,}$"#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.range(of: #"^C[A-Za-z0-9]{4,20}(IYG|sokG|s4kG)$"#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.count >= 6,
           trimmed.count <= 22,
           trimmed.range(of: #"^[A-Za-z0-9]+$"#, options: .regularExpression) != nil,
           trimmed.range(of: #"[A-Z]"#, options: .regularExpression) != nil,
           trimmed.range(of: #"[a-z]"#, options: .regularExpression) != nil,
           trimmed.range(of: #"[0-9]"#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.count >= 12,
           trimmed.range(of: #"^[A-Za-z0-9+/=_-]+$"#, options: .regularExpression) != nil,
           trimmed.range(of: #"[+/=_-]"#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.count >= 24,
           trimmed.range(of: #"^[A-Za-z0-9]+$"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    static func safePhoneNumber(from value: String?) -> String? {
        guard let candidate = value?.trimmingCharacters(in: .whitespacesAndNewlines), !candidate.isEmpty else {
            return nil
        }

        let lowercasedCandidate = candidate.lowercased()
        guard !lowercasedCandidate.contains("@lid"),
              !lowercasedCandidate.contains("@g.us"),
              !candidate.contains(";"),
              !candidate.contains(",") else {
            return nil
        }

        guard let atIndex = candidate.firstIndex(of: "@") else {
            return nil
        }

        let localPart = String(candidate[..<atIndex])
        let domainAndSuffix = String(candidate[candidate.index(after: atIndex)...]).lowercased()
        let domain = domainAndSuffix.split(whereSeparator: { $0 == "/" || $0 == ":" }).first.map(String.init)
        guard domain == "s.whatsapp.net" else {
            return nil
        }

        let phoneCandidate = localPart.split(whereSeparator: { $0 == "/" || $0 == ":" }).first.map(String.init) ?? ""
        let digits = phoneCandidate.filter(\.isNumber)
        guard digits.count >= 7, digits.count <= 15, digits == phoneCandidate else {
            return nil
        }
        return "+\(digits)"
    }
}
