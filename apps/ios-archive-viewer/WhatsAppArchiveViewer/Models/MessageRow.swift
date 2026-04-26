import Foundation

enum MediaAttachmentKind: String, Hashable {
    case photo
    case video
    case audio
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
        case .audio:
            return "Audio attachment"
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
            return "VOICE CALL"
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

struct MediaMetadata: Hashable {
    let itemID: Int64?
    let localPath: String?
    let fileName: String?
    let title: String?
    let mimeType: String?
    let fileSize: Int64?
    let isFileAvailableInArchive: Bool
    let kind: MediaAttachmentKind
}

struct MessageRow: Identifiable, Hashable {
    let id: Int64
    let isFromMe: Bool
    let senderJID: String?
    let pushName: String?
    let groupMemberContactName: String?
    let groupMemberFirstName: String?
    let groupMemberJID: String?
    let profilePushName: String?
    let text: String?
    let messageDate: Date?
    let messageType: Int?
    let groupEventType: Int?
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
    }

    var safeSenderPhoneNumber: String? {
        DisplayNameSanitizer.safePhoneNumber(from: groupMemberJID)
            ?? DisplayNameSanitizer.safePhoneNumber(from: senderJID)
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

    private static func isSystemMessageType(_ value: Int?) -> Bool {
        value == 6 || value == 10
    }

    private static func isCallMessageType(_ value: Int?) -> Bool {
        value == 59 || value == 66
    }
}

struct MessagePaginationCursor: Hashable {
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
