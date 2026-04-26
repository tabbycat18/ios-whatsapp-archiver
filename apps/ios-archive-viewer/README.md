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
- Uses `ContactsV2.sqlite` when available to improve contact names and link phone-JID/`@lid` sessions only when they map to the same contact row.
- Merges duplicate chat sessions only when they share a strong identifier, such as the same `ZCONTACTJID` or the same unambiguous ContactsV2 identity.
- Classifies unresolved duplicate-title entries conservatively so real separate conversations stay visible while technical archive fragments do not clutter normal browsing.
- Discovers `ZWAMEDIAITEM` metadata when the table and columns are available.
- Shows text messages, inline photos, tap-to-play video previews, simple audio playback, and conservative placeholders for unsupported media/system rows.
- Checks whether referenced media files appear available under the selected archive root.
- Uses the extracted WhatsApp chat wallpaper as the message background when a generic wallpaper file is present at the selected archive root.
- Avoids showing raw JIDs or internal sender identifiers in the normal message UI.
- Shows safely extracted phone numbers for unsaved group senders when the sender JID can be reduced to digits only.

Media files stay local. The app renders only visible message attachments lazily
and keeps missing or unresolved files as placeholders.

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

### Milestone 4 Chat Media Rendering

- Renders available photo attachments inline after downsampling.
- Shows available videos as tap-to-play attachments with lazy thumbnails when thumbnail generation succeeds.
- Plays available audio and voice attachments with a simple play/pause control.
- Shows the archive wallpaper behind messages when `current_wallpaper.jpg` or `current_wallpaper_dark.jpg` exists next to `ChatStorage.sqlite`.
- Keeps unsupported, missing, or unreadable media as placeholders.
- Loads media only for visible rows and does not scan or preload all archive media.

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
- Group sender names use friendly names when the archive provides one, including profile push names stored in `ChatStorage.sqlite` and optional ContactsV2 names. Unsaved senders may show a safely extracted phone number only from classic phone-based WhatsApp JIDs. `@lid` identifiers and unresolved sender tokens are treated as opaque, so the UI shows "Unknown sender" rather than risk showing a wrong name or number.
- Message classification is conservative. Known media placeholders, likely voice call rows, deleted rows, and system notices are labeled without exposing raw database identifiers. Unknown mappings stay generic instead of guessing unsupported WhatsApp internals.
- Chat sorting prefers the latest real user-visible conversation row when possible and excludes known system-notice message types from the primary latest-date calculation. It falls back to broader activity dates only when no relevant message date is available.
- Split sessions can exist in old archives. The viewer merges sessions with strong identity evidence, but does not merge rows by title alone because that can combine unrelated people with the same display name.
- Duplicate-title rows with real user-visible text, media, or call evidence stay visible as separate conversations. Duplicate/system-only rows and tiny no-visible-message archive fragments are hidden from normal browsing and chat-title search instead of being merged or deleted. Uncertain larger archive entries remain visible with a cautious label.
- Media path resolution checks several archive-root-relative layouts, including `Media/` and `Message/Media/`. The normal UI does not print full private media paths.
- Chat wallpaper resolution checks generic archive-root files named `current_wallpaper.jpg` and `current_wallpaper_dark.jpg`.
- Media rendering is lazy. Images are downsampled before display, video thumbnails are generated only for visible video rows, and audio playback starts only after the user taps play.

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
- Search for duplicate-title contacts and confirm real separate conversations remain visible while system-only fragments do not drive normal results.
- Scroll upward and confirm older rows load automatically near the top.
- Confirm ordering remains oldest-to-newest.
- Confirm sender direction and dates remain correct.
- Confirm media placeholders still appear.
- Confirm available photos render inline without large layout jumps.
- Confirm available videos open in the video preview only after tapping.
- Confirm available audio or voice rows can play and pause.
- Confirm the chat wallpaper appears behind messages when `current_wallpaper.jpg` is present in the selected archive folder.
- Confirm missing or unreadable media remains a clean placeholder.
- Confirm call and system rows use neutral labels instead of generic unsupported text where possible.
- Confirm the viewer does not auto-scroll back to newest after loading older messages.
- Confirm raw/debug identifiers are not shown in the normal message UI.
- Confirm unresolved group senders show "Unknown sender" instead of raw opaque tokens.
- Confirm chat list dates for duplicate-title conversations come from user-visible text, media, or call rows rather than security/system-only fragments.
- Confirm media rendering does not break automatic older-message loading.
- Avoid printing private message contents or full private filesystem paths during debugging.

## Large Archive Transfer Notes

Real extracted WhatsApp archives can be tens of GB and can contain more than 100k files. Raw folder transfer to iPhone can be slow even when the Mac and iPhone are modern. The bottleneck can be the transfer method, number of files, iOS file handling, iCloud sync, or cable speed.

Recommended current development workflow:

- Start with only `ChatStorage.sqlite` and any SQLite sidecars to validate chat browsing and full-history pagination.
- Use a small media subset when testing media rendering changes.
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

- The per-chat media library is not implemented yet.
- Document, link-preview, location, contact-card, and sticker rendering remain placeholders.
- ContactsV2 enrichment is intentionally conservative and may not resolve every historical contact edge case yet.
- ContactsV2 improves identity resolution, but duplicate-title sessions can still represent either real separate chats or archive fragments that need conservative classification.
- Persistent archive bookmarks and polished import management are future work.
- App document sharing through Finder is not configured yet; use the Files picker with a local or iCloud Drive archive folder.
- Zip/package import is not implemented yet.
