import Foundation

enum ChatSessionClassification: String, Hashable {
    case normalConversation
    case separateConversation
    case statusStoryFragment
    case archiveFragment
    case systemOnlyFragment
    case unknown
}

enum ChatWallpaperTheme: String, CaseIterable, Identifiable {
    case archiveDefault
    case classic
    case softPattern
    case demo
    case plain

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .archiveDefault:
            return "Default"
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
            return "Use the existing wallpaper from the selected archive when available."
        case .classic:
            return "A subtle chat-style pattern with warm light and deep dark variants."
        case .softPattern:
            return "A quiet app-style pattern tuned for readable message bubbles."
        case .demo:
            return "A new synthetic sample pattern. Use Default to keep the demo archive wallpaper."
        case .plain:
            return "Disable wallpaper and use a simple background."
        }
    }
}

struct ChatSummary: Identifiable, Hashable {
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
