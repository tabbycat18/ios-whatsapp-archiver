# iOS WhatsApp Archive Viewer

This is a native SwiftUI iPhone and iPad app for local, read-only inspection of an extracted iOS WhatsApp archive. It is isolated from the original Windows/C++ Android `msgstore.db` viewer.

Private WhatsApp data must not be committed. Keep `ChatStorage.sqlite`, `ContactsV2.sqlite`, `Media/`, `Message/`, and generated exports under ignored local data folders.

## Open in Xcode

Open the project from the repository root:

```bash
open apps/ios-archive-viewer/WhatsAppArchiveViewer.xcodeproj
```

Build and run with full Xcode on an iOS simulator or device. Command Line Tools alone are not enough for simulator builds.

## What the App Does

- Opens an extracted archive folder containing `ChatStorage.sqlite`, or `ChatStorage.sqlite` directly.
- Copies `ChatStorage.sqlite` and SQLite sidecars into the app sandbox before opening them.
- Opens SQLite with `SQLITE_OPEN_READONLY`.
- Sets `PRAGMA query_only = ON`.
- Loads chat sessions from `ZWACHATSESSION`.
- Searches loaded chat titles in memory.
- Loads messages for the selected chat from `ZWAMESSAGE`.
- Discovers `ZWAMEDIAITEM` metadata when the table and columns are available.
- Shows text messages and conservative media/system placeholders.
- Checks whether referenced media files appear available under the selected archive root.
- Avoids showing raw JIDs or internal sender identifiers in the normal message UI.

The app does not render photos, videos, audio, thumbnails, or binary media yet.

## Current State

### Milestone 1 Validated

- Opens a real extracted iPhone `ChatStorage.sqlite`.
- Loads the chat list and large chats.
- Preserves message order, dates, and sender direction.
- Keeps the app responsive by loading only the latest batch for a selected chat.

### Milestone 2 Media Metadata Discovery

- Discovers available `ZWAMEDIAITEM` columns at runtime.
- Joins media metadata to message rows when the schema supports it.
- Shows clearer placeholders for empty-text media messages, such as photo, video, audio, or generic media attachments.
- Attempts safe relative media path resolution under the selected archive root without loading media files.
- Keeps the database read-only.

### Milestone 2.5 Full-History Pagination

- Opens a selected chat with only the latest 500 messages loaded initially.
- Loads older messages automatically in additional batches when scrolling upward.
- Uses stable keyset pagination by message date and primary key instead of `OFFSET`.
- Prepends older batches while keeping the UI ordered oldest-to-newest.
- Keeps initial auto-scroll to the latest message, but does not jump back to the bottom after loading older messages.
- Keeps media metadata and path discovery populated for older loaded messages.

The app does not load every message at once because large WhatsApp chats can contain many thousands of rows. Incremental loading keeps memory use and UI updates bounded while still allowing full-history reading. Scrolling upward loads older history as needed.

### Current UI Policies

- Chat search filters loaded chat titles only. It does not search message contents.
- Raw JIDs and internal sender identifiers are hidden in the normal UI.
- Group sender names use friendly names when the archive provides one; otherwise the UI shows "Unknown sender".
- Message classification is conservative. Unknown mappings stay generic instead of guessing unsupported WhatsApp internals.
- Chat sorting uses the chat's last-message pointer date when available, then falls back to the maximum message date and a sanitized session date. This may still differ from WhatsApp where the app uses private ranking logic that has not been mapped.

## Development Data

For simulator development, a local development copy of `ChatStorage.sqlite` can be placed in the app container's Documents folder as:

```text
Documents/ChatStorage.sqlite
```

If sidecar files are present, copy them next to it too:

```text
Documents/ChatStorage.sqlite-wal
Documents/ChatStorage.sqlite-shm
Documents/ChatStorage.sqlite-journal
```

The app also has an Open Archive action that can select either an extracted archive folder containing `ChatStorage.sqlite` or the database file directly. Picking the containing folder is preferred because the selected folder becomes the archive root for media availability checks. The app copies only the database and sidecars into Application Support; it does not copy media binaries into the app sandbox.

## Testing Notes

- Test with a large chat and confirm the latest 500 messages appear first.
- Search for a known chat title, then clear search and confirm all chats return.
- Scroll upward and confirm older rows load automatically near the top.
- Confirm ordering remains oldest-to-newest.
- Confirm sender direction and dates remain correct.
- Confirm media placeholders still appear.
- Confirm the viewer does not auto-scroll back to newest after loading older messages.
- Confirm raw/debug identifiers are not shown in the normal message UI.
- Avoid printing private message contents or full private filesystem paths during debugging.

## Large Archive Transfer Notes

Real extracted WhatsApp archives can be tens of GB and can contain more than 100k files. Raw folder transfer to iPhone can be slow even when the Mac and iPhone are modern. The bottleneck can be the transfer method, number of files, iOS file handling, iCloud sync, or cable speed.

Recommended current development workflow:

- Start with only `ChatStorage.sqlite` and any SQLite sidecars to validate chat browsing and full-history pagination.
- Use a small media subset when testing media path discovery or future rendering work.
- Avoid repeatedly transferring the full archive during development.
- Transfer the full raw media archive only when the full media set is needed.

Transfer options and limitations:

- Raw folder transfer through Files, iCloud Drive, AirDrop, or another provider can work, but it may be slow for very large archives.
- iCloud Drive is optional and user-managed. Copy/paste is safer than drag/drop if you want to keep the original Mac copy because dragging may move instead of copy depending on source and destination.
- Large folders may appear in iCloud Drive locally before cloud sync has finished. Wait for upload/sync completion, then ensure the folder is downloaded locally on iPhone before opening it.
- AirDrop can work, but very large transfers may be slow and iPhone may need additional time to save the received data after progress appears mostly complete.
- Zip/package transfer is an experiment, not current app support. The app does not open zip files directly; unpack the archive first and select the folder containing `ChatStorage.sqlite`.

Packaging may still be useful to test because one large file can be easier to transfer than more than 100k small files. It may not save much space, and packaging/unpacking requires substantial extra free storage.

## Privacy Warnings

- Do not commit extracted archives, WhatsApp databases, media folders, generated exports, or screenshots with private content.
- Keep local archives under ignored folders such as `data/` or `exports/`.
- Check `git status --short --ignored` before every commit.

## Limitations

- Media rendering is not implemented yet.
- Thumbnails and binary media are not loaded into memory yet.
- `ContactsV2.sqlite` is not used for contact enrichment yet.
- Persistent archive bookmarks and polished import management are future work.
- App document sharing through Finder is not configured yet; use the Files picker with a local or iCloud Drive archive folder.
- Zip/package import is not implemented yet.
