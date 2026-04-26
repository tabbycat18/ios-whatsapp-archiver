import Foundation

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

    var isGroupChat: Bool {
        contactJID?.contains("@g.us") == true
    }
}
