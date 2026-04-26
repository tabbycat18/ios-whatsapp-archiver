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
    case callOrSystem
    case system
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
        case .callOrSystem:
            return "Call or system message"
        case .system:
            return "System message"
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
        DisplayNameSanitizer.friendlyName(pushName)
            ?? DisplayNameSanitizer.friendlyName(groupMemberContactName)
            ?? DisplayNameSanitizer.friendlyName(groupMemberFirstName)
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
}
