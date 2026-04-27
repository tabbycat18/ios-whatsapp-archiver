# Architecture

ios-whatsapp-archiver is split into local extraction tools and a native SwiftUI archive viewer.

## Tools

`tools/extract_ios_whatsapp_backup.py` reads an iPhone backup manifest and extracts WhatsApp shared-container files to a local output folder. It supports:

- encrypted backups through the optional `iphone-backup-decrypt` package;
- unencrypted backups through direct `Manifest.db` lookup;
- a default WhatsApp shared-container domain pattern of `%whatsapp%WhatsApp%.shared`;
- preserved domain and relative-path output folders.

`tools/export_ios_whatsapp_html.py` is a proof-of-concept local HTML exporter. Generated HTML contains private chat content and must stay out of version control. The SwiftUI viewer is the current app path.

## Extracted Archive

The primary archive folder is the extracted WhatsApp shared-container folder, usually similar to:

```text
AppDomainGroup-group.net.whatsapp.WhatsApp.shared/
```

The viewer currently focuses on:

- `ChatStorage.sqlite`
- SQLite sidecars for `ChatStorage.sqlite` when present
- `ZWACHATSESSION`
- `ZWAMESSAGE`
- `ZWAMEDIAITEM` metadata when present and joinable
- relative media paths under `Media/` and `Message/`

`ContactsV2.sqlite` is preserved by extraction and used conservatively by the
viewer when identifiers map unambiguously.

## SwiftUI Viewer

The iOS app lives under `apps/ios-archive-viewer/`. It is an iPhone/iPad SwiftUI target.

The app can open:

- an extracted archive folder containing `ChatStorage.sqlite`, or
- `ChatStorage.sqlite` directly.

The app starts with a local archive selection screen built around two account
slots: WhatsApp and WhatsApp Business. Adding an archive stores a small saved
record with bookmark metadata, local display label, archive kind, last-opened
date, and chat count when available. Saved labels are app metadata only; editing
them does not rename or move archive folders. The saved records stay in app
storage and do not upload archive contents.

When an archive is opened, the app resolves the saved bookmark, starts
security-scoped access when iOS requires it, opens the selected database in
place with `SQLITE_OPEN_READONLY`, and sets `PRAGMA query_only = ON`. If a
bookmark is stale or the external archive moved, the library marks the archive
as needing reselecting and lets the user relink it.

When an archive is opened, the chat list title is simply `Chats`; the selected
archive folder name is kept out of the chat-list header.

The selected archive folder remains the archive root for media availability
checks. Media binaries, thumbnails, and full archives are not copied into the
app sandbox and are not loaded into memory. Removing a saved archive record only
removes the app's metadata; it does not delete archive files.

The app does not currently open zip files or packaged archives directly. If a user transfers a packaged archive today, it must be unpacked first and the unpacked folder containing `ChatStorage.sqlite` must be selected.

## Optional iPhone Contacts Matching

The viewer can optionally use the iOS Contacts framework to improve display
names for phone-based WhatsApp participants. The app does not ask for Contacts
permission on first launch or while opening an archive. The user must enable it
from the chat list More menu.

Contacts access is read-only. When authorized, the app loads contacts in the
background and builds an in-memory mapping from conservative phone keys to
display names. Duplicate phone keys are used only when they map to one
unambiguous display name. The full contact list is not written to disk and is
not uploaded.

Phone normalization accepts classic phone WhatsApp JIDs such as
`41791234567@s.whatsapp.net` and contact phone numbers with common formatting.
It rejects `@lid`, `@g.us`, opaque tokens, base64-like values, and uncertain
local numbers. Swiss local numbers with a leading zero are normalized to `41...`
only when the current locale is Switzerland and the shape is otherwise clear.

Display-name priority remains conservative:

- one-to-one chat titles keep existing archive or ContactsV2 friendly names
  before using an iPhone Contacts match;
- group sender labels prefer archive-provided group member or push names,
  ContactsV2 names, then optional iPhone Contacts matches;
- safe phone fallbacks are shown only for classic phone JIDs;
- unresolved opaque senders stay "Unknown sender".

## Data Loading

Chat summaries are loaded from `ZWACHATSESSION` with per-chat message counts derived from `ZWAMESSAGE`.

Messages are loaded per selected chat only. There is no global message loading path.

Initial chat open loads the latest 250 messages, ordered newest-first in SQL and then displayed oldest-to-newest. Full-history access uses keyset pagination with a stable cursor:

- oldest loaded message date;
- oldest loaded message primary key.

Older batches query rows before that cursor using `ZMESSAGEDATE` and `Z_PK`, then reverse the fetched batch before prepending it to the UI.

## Media Metadata Discovery

At database open, the viewer discovers available message and media columns. If `ZWAMEDIAITEM` is present and joinable through `ZMESSAGE`, message queries join media metadata without requiring media files to be loaded.

The UI currently shows placeholders such as photo, video, audio, or generic media attachment. It also records whether the referenced media path appears available under the selected archive root. Photo, video, audio, and document messages render their `ZWAMESSAGE.ZTEXT` caption under the attachment in the same bubble when present.

## Transfer Constraints

Large real-world WhatsApp archives can be tens of GB and can contain more than 100k files. Raw folder transfer to iPhone can be slow because the bottleneck may be the transfer method, file count, iOS file handling, iCloud sync, or cable speed.

The project itself does not upload archive data. iCloud Drive, AirDrop, Finder, Files, external-drive, or third-party provider transfers are user-managed.

The current architecture is best tested incrementally:

- database-only transfer for chat list, message loading, and full-history pagination;
- small media subsets for media path discovery and media rendering checks;
- full raw archive transfer only when the complete media set is required.

Packaged archive import is a likely future design direction. One archive file could be imported by the app, unpacked or indexed locally, and avoid pushing thousands of individual files through app document sharing. That workflow is not implemented yet.

## Future Work

- Experiment with packaged archive import.
- Expand sender/contact enrichment from `ContactsV2.sqlite` and safe phone
  mappings that can bridge opaque identifiers without guessing.
- Add synthetic public fixtures for repeatable tests without private data.
