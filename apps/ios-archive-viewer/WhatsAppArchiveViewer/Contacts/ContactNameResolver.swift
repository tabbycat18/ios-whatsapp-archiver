import Foundation

enum ContactNameResolverStatus: Hashable {
    case notEnabled
    case loading
    case enabled
    case permissionDenied
    case restricted

    var displayText: String {
        switch self {
        case .notEnabled:
            return "Not enabled"
        case .loading:
            return "Loading"
        case .enabled:
            return "Enabled"
        case .permissionDenied:
            return "Permission denied"
        case .restricted:
            return "Restricted"
        }
    }

    var explanation: String {
        switch self {
        case .notEnabled:
            return "Use iPhone Contacts to show saved names for phone-based WhatsApp participants."
        case .loading:
            return "Loading contacts locally for this app session."
        case .enabled:
            return "Contacts are used locally for display-name matching."
        case .permissionDenied:
            return "Allow Contacts in iOS Settings to match saved contact names."
        case .restricted:
            return "Contacts access is restricted on this device."
        }
    }
}

@MainActor
final class ContactNameResolver: ObservableObject {
    @Published private(set) var status: ContactNameResolverStatus
    @Published private(set) var changeToken = UUID()

    private let defaults: UserDefaults
    private let enabledDefaultsKey = "DeviceContactsMatchingEnabled.v1"
    private let deviceContactsResolver: DeviceContactsResolver
    private var index = DeviceContactIndex.empty
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0

    init(
        defaults: UserDefaults = .standard,
        deviceContactsResolver: DeviceContactsResolver = DeviceContactsResolver()
    ) {
        self.defaults = defaults
        self.deviceContactsResolver = deviceContactsResolver

        let storedEnabled = defaults.bool(forKey: enabledDefaultsKey)
        let authorizationStatus = DeviceContactsResolver.authorizationStatus()
        if storedEnabled {
            status = Self.status(from: authorizationStatus, storedEnabled: true)
        } else {
            status = authorizationStatus == .denied ? .permissionDenied : .notEnabled
        }

        #if DEBUG
        if storedEnabled, authorizationStatus == .authorized {
            print("[Launch] deferred device Contacts matching until an archive opens")
        }
        #endif
    }

    deinit {
        loadTask?.cancel()
    }

    func enableContactMatching() {
        guard status != .loading else { return }

        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        status = .loading
        loadTask = Task { [weak self] in
            guard let self else { return }
            let authorizationStatus = await deviceContactsResolver.requestAccessIfNeeded()
            await MainActor.run {
                self.defaults.set(authorizationStatus == .authorized, forKey: self.enabledDefaultsKey)
            }

            guard authorizationStatus == .authorized else {
                await MainActor.run {
                    self.index = .empty
                    self.status = Self.status(from: authorizationStatus, storedEnabled: false)
                    self.changeToken = UUID()
                }
                return
            }

            await loadContactsFromAuthorizedState(generation: generation)
        }
    }

    func disableContactMatching() {
        defaults.set(false, forKey: enabledDefaultsKey)
        loadGeneration += 1
        loadTask?.cancel()
        index = .empty
        status = .notEnabled
        changeToken = UUID()
    }

    func loadContactsIfEnabled() {
        guard defaults.bool(forKey: enabledDefaultsKey),
              DeviceContactsResolver.authorizationStatus() == .authorized,
              loadTask == nil,
              status == .loading
        else {
            return
        }
        loadContacts()
    }

    func displayName(for identifiers: [String?]) -> String? {
        guard status == .enabled || status == .loading else {
            return nil
        }

        for identifier in identifiers {
            if let displayName = index.displayName(for: identifier) {
                return displayName
            }
        }
        return nil
    }

    private func loadContacts() {
        loadTask?.cancel()
        status = .loading
        loadGeneration += 1
        let generation = loadGeneration
        loadTask = Task { [weak self] in
            guard let self else { return }
            await loadContactsFromAuthorizedState(generation: generation)
        }
    }

    private func loadContactsFromAuthorizedState(generation: Int? = nil) async {
        do {
            let loadedIndex = try await loadContactIndexWithTimeout()
            guard generation == nil || generation == loadGeneration else { return }
            await MainActor.run {
                self.index = loadedIndex
                self.status = .enabled
                self.changeToken = UUID()
            }
        } catch {
            guard generation == nil || generation == loadGeneration else { return }
            await MainActor.run {
                self.index = .empty
                self.status = DeviceContactsResolver.authorizationStatus() == .authorized ? .enabled : .permissionDenied
                self.changeToken = UUID()
            }
        }
    }

    private func loadContactIndexWithTimeout() async throws -> DeviceContactIndex {
        let deviceContactsResolver = self.deviceContactsResolver
        return try await withThrowingTaskGroup(of: DeviceContactIndex.self) { group in
            group.addTask {
                try await deviceContactsResolver.loadContactIndex()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(8))
                return DeviceContactIndex.empty
            }

            guard let index = try await group.next() else {
                group.cancelAll()
                return DeviceContactIndex.empty
            }
            group.cancelAll()
            return index
        }
    }

    private static func status(
        from authorizationStatus: DeviceContactsAuthorization,
        storedEnabled: Bool
    ) -> ContactNameResolverStatus {
        switch authorizationStatus {
        case .notDetermined:
            return storedEnabled ? .notEnabled : .notEnabled
        case .authorized:
            return storedEnabled ? .loading : .notEnabled
        case .denied:
            return .permissionDenied
        case .restricted:
            return .restricted
        }
    }
}
