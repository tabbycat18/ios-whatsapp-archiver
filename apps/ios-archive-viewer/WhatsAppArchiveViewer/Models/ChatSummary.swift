import Foundation

enum ChatSessionClassification: String, Hashable, Sendable {
    case normalConversation
    case separateConversation
    case statusStoryFragment
    case archiveFragment
    case systemOnlyFragment
    case unknown
}

enum ChatWallpaperTheme: String, CaseIterable, Identifiable, Sendable {
    case archiveDefault
    case classic
    case softPattern
    case demo
    case plain

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .archiveDefault:
            return "Archive Default"
        case .classic:
            return "Classic"
        case .softPattern:
            return "Soft Pattern"
        case .demo:
            return "Demo"
        case .plain:
            return "Plain"
        }
    }

    var detailText: String {
        switch self {
        case .archiveDefault:
            return "Use the selected archive's wallpaper when available."
        case .classic:
            return "The recovered dense doodle wallpaper, with matching light and dark variants."
        case .softPattern:
            return "The previous demo companion pattern, with matching light and dark variants."
        case .demo:
            return "Use the bundled demo archive wallpaper pair."
        case .plain:
            return "Disable wallpaper and use a simple background."
        }
    }
}

struct ChatSummary: Identifiable, Hashable, Sendable {
    let id: Int64
    let sessionIDs: [Int64]
    let contactJID: String?
    let contactIdentifier: String?
    let profilePhotoIdentifiers: [String]
    let partnerName: String?
    let title: String
    let detailText: String
    let messageCount: Int
    let latestMessageDate: Date?
    let searchableTitle: String
    let classification: ChatSessionClassification
    var profilePhotoURL: URL?

    var isGroupChat: Bool {
        contactJID?.contains("@g.us") == true
    }
}
