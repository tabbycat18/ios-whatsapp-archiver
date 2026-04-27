import Foundation

enum ArchiveSelectionError: LocalizedError {
    case wrongFolderSelected
    case requiredFilesMissing
    case permissionDenied
    case unsupportedArchiveStructure

    var errorDescription: String? {
        switch self {
        case .wrongFolderSelected:
            return "Wrong folder selected. Choose the extracted WhatsApp archive folder that contains ChatStorage.sqlite, or its parent export folder."
        case .requiredFilesMissing:
            return "Required archive file missing. The app could not find ChatStorage.sqlite in the selected archive."
        case .permissionDenied:
            return "The app could not access the selected archive. Reopen the picker and grant access to the folder."
        case .unsupportedArchiveStructure:
            return "Unsupported archive structure. Choose one extracted WhatsApp archive folder, not a folder containing multiple archives."
        }
    }
}

struct ResolvedArchiveSelection {
    let selectedResourceIsDirectory: Bool
    let archiveRootURL: URL
    let databaseURL: URL
}

enum ArchiveSelectionResolver {
    static func resolve(_ selectedURL: URL, fileManager: FileManager = .default) throws -> ResolvedArchiveSelection {
        let selectedURL = selectedURL.standardizedFileURL
        let selectedResourceIsDirectory = try isDirectory(selectedURL)

        if selectedResourceIsDirectory {
            let archiveRootURL = try resolveDirectory(selectedURL, fileManager: fileManager)
            return ResolvedArchiveSelection(
                selectedResourceIsDirectory: true,
                archiveRootURL: archiveRootURL,
                databaseURL: databaseURL(in: archiveRootURL)
            )
        }

        let archiveRootURL = try resolveFile(selectedURL, fileManager: fileManager)
        return ResolvedArchiveSelection(
            selectedResourceIsDirectory: false,
            archiveRootURL: archiveRootURL,
            databaseURL: databaseURL(in: archiveRootURL)
        )
    }

    private static func resolveDirectory(_ selectedURL: URL, fileManager: FileManager) throws -> URL {
        if hasDatabase(in: selectedURL, fileManager: fileManager) {
            return selectedURL
        }

        let parentURL = selectedURL.deletingLastPathComponent().standardizedFileURL
        if parentURL != selectedURL, hasDatabase(in: parentURL, fileManager: fileManager) {
            return parentURL
        }

        let nestedArchiveRoots = try immediateNestedArchiveRoots(in: selectedURL, fileManager: fileManager)
        if nestedArchiveRoots.count == 1, let archiveRootURL = nestedArchiveRoots.first {
            return archiveRootURL
        }
        if nestedArchiveRoots.count > 1 {
            throw ArchiveSelectionError.unsupportedArchiveStructure
        }

        throw ArchiveSelectionError.wrongFolderSelected
    }

    private static func resolveFile(_ selectedURL: URL, fileManager: FileManager) throws -> URL {
        let parentURL = selectedURL.deletingLastPathComponent().standardizedFileURL
        if selectedURL.lastPathComponent == "ChatStorage.sqlite", hasDatabase(in: parentURL, fileManager: fileManager) {
            return parentURL
        }
        if hasDatabase(in: parentURL, fileManager: fileManager) {
            return parentURL
        }

        throw ArchiveSelectionError.requiredFilesMissing
    }

    private static func immediateNestedArchiveRoots(in selectedURL: URL, fileManager: FileManager) throws -> [URL] {
        let childURLs: [URL]
        do {
            childURLs = try fileManager.contentsOfDirectory(
                at: selectedURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
        } catch {
            throw ArchiveSelectionError.permissionDenied
        }

        return childURLs
            .filter { (try? isDirectory($0)) == true }
            .map { $0.standardizedFileURL }
            .filter { hasDatabase(in: $0, fileManager: fileManager) }
    }

    private static func hasDatabase(in directoryURL: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(
            atPath: databaseURL(in: directoryURL).path,
            isDirectory: &isDirectory
        ) && !isDirectory.boolValue
    }

    private static func databaseURL(in archiveRootURL: URL) -> URL {
        archiveRootURL
            .appendingPathComponent("ChatStorage.sqlite")
            .standardizedFileURL
    }

    private static func isDirectory(_ url: URL) throws -> Bool {
        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            return values.isDirectory == true
        } catch {
            throw ArchiveSelectionError.permissionDenied
        }
    }
}
