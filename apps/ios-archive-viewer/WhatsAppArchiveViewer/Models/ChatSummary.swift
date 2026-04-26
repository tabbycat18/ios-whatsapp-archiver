import Foundation

enum ChatSessionClassification: String, Hashable {
    case normalConversation
    case separateConversation
    case archiveFragment
    case systemOnlyFragment
    case unknown
}

struct ChatSummary: Identifiable, Hashable {
    let id: Int64
    let sessionIDs: [Int64]
    let contactJID: String?
    let contactIdentifier: String?
    let partnerName: String?
    let title: String
    let detailText: String
    let messageCount: Int
    let latestMessageDate: Date?
    let searchableTitle: String
    let classification: ChatSessionClassification

    var isGroupChat: Bool {
        contactJID?.contains("@g.us") == true
    }
}
