import Contacts
import Foundation

struct DeviceContactEntry: Hashable {
    let displayName: String
    let phoneKeys: [String]
}

struct DeviceContactIndex: Hashable {
    static let empty = DeviceContactIndex(namesByPhoneKey: [:])

    private let namesByPhoneKey: [String: String]

    init(entries: [DeviceContactEntry]) {
        var candidates: [String: Set<String>] = [:]

        for entry in entries {
            guard let displayName = DisplayNameSanitizer.friendlyName(entry.displayName) else {
                continue
            }
            for key in Set(entry.phoneKeys) {
                candidates[key, default: []].insert(displayName)
            }
        }

        namesByPhoneKey = candidates.compactMapValues { names in
            names.count == 1 ? names.first : nil
        }
    }

    init(candidatesByPhoneKey candidates: [String: Set<String>]) {
        namesByPhoneKey = candidates.compactMapValues { names in
            names.count == 1 ? names.first : nil
        }
    }

    private init(namesByPhoneKey: [String: String]) {
        self.namesByPhoneKey = namesByPhoneKey
    }

    func displayName(for identifier: String?) -> String? {
        guard let key = PhoneNumberNormalizer.comparableKey(from: identifier, source: .whatsAppJID) else {
            return nil
        }
        return namesByPhoneKey[key]
    }
}

enum DeviceContactsAuthorization: Hashable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

actor DeviceContactsResolver {
    private let contactStore: CNContactStore
    private let locale: Locale

    init(contactStore: CNContactStore = CNContactStore(), locale: Locale = .current) {
        self.contactStore = contactStore
        self.locale = locale
    }

    nonisolated static func authorizationStatus() -> DeviceContactsAuthorization {
        authorization(from: CNContactStore.authorizationStatus(for: .contacts))
    }

    func requestAccessIfNeeded() async -> DeviceContactsAuthorization {
        let currentStatus = Self.authorizationStatus()
        guard currentStatus == .notDetermined else {
            return currentStatus
        }

        let wasGranted = await withCheckedContinuation { continuation in
            contactStore.requestAccess(for: .contacts) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
        return wasGranted ? .authorized : Self.authorizationStatus()
    }

    func loadContactIndex() async throws -> DeviceContactIndex {
        let locale = self.locale
        let task = Task.detached(priority: .background) {
            try Self.loadContactIndex(locale: locale)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private nonisolated static func loadContactIndex(locale: Locale) throws -> DeviceContactIndex {
        guard Self.authorizationStatus() == .authorized else {
            return .empty
        }

        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]
        let contactStore = CNContactStore()
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .none
        request.unifyResults = false

        var candidates: [String: Set<String>] = [:]
        try contactStore.enumerateContacts(with: request) { contact, stop in
            guard !Task.isCancelled else {
                stop.pointee = true
                return
            }
            let displayName = Self.displayName(for: contact)
            guard let friendlyDisplayName = DisplayNameSanitizer.friendlyName(displayName) else {
                return
            }
            let phoneKeys = contact.phoneNumbers.compactMap { phoneNumber in
                PhoneNumberNormalizer.comparableKey(
                    from: phoneNumber.value.stringValue,
                    source: .contactPhoneNumber,
                    locale: locale
                )
            }
            for key in Set(phoneKeys) {
                candidates[key, default: []].insert(friendlyDisplayName)
            }
        }

        return DeviceContactIndex(candidatesByPhoneKey: candidates)
    }

    private nonisolated static func displayName(for contact: CNContact) -> String {
        let combinedName = [contact.givenName, contact.familyName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if let friendlyName = DisplayNameSanitizer.friendlyName(combinedName) {
            return friendlyName
        }

        return contact.organizationName
    }

    private nonisolated static func authorization(from status: CNAuthorizationStatus) -> DeviceContactsAuthorization {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .limited:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .denied
        }
    }
}
