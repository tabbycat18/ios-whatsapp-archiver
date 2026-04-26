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

`ContactsV2.sqlite` is preserved by extraction but is not used for contact enrichment yet.

## SwiftUI Viewer

The iOS app lives under `apps/ios-archive-viewer/`. It is an iPhone/iPad SwiftUI target.

The app can open:

- an extracted archive folder containing `ChatStorage.sqlite`, or
- `ChatStorage.sqlite` directly.

When an archive is opened, the app copies `ChatStorage.sqlite` and SQLite sidecars into its Application Support folder. It then opens the copied database with `SQLITE_OPEN_READONLY` and sets `PRAGMA query_only = ON`.

The selected archive folder remains the archive root for media availability checks. Media binaries and thumbnails are not copied into the app sandbox and are not loaded into memory.

The app does not currently open zip files or packaged archives directly. If a user transfers a packaged archive today, it must be unpacked first and the unpacked folder containing `ChatStorage.sqlite` must be selected.

## Data Loading

Chat summaries are loaded from `ZWACHATSESSION` with per-chat message counts derived from `ZWAMESSAGE`.

Messages are loaded per selected chat only. There is no global message loading path.

Initial chat open loads the latest 500 messages, ordered newest-first in SQL and then displayed oldest-to-newest. Full-history access uses keyset pagination with a stable cursor:

- oldest loaded message date;
- oldest loaded message primary key.

Older batches query rows before that cursor using `ZMESSAGEDATE` and `Z_PK`, then reverse the fetched batch before prepending it to the UI.

## Media Metadata Discovery

At database open, the viewer discovers available message and media columns. If `ZWAMEDIAITEM` is present and joinable through `ZMESSAGE`, message queries join media metadata without requiring media files to be loaded.

The UI currently shows placeholders such as photo, video, audio, or generic media attachment. It also records whether the referenced media path appears available under the selected archive root.

Media rendering is future work.

## Transfer Constraints

Large real-world WhatsApp archives can be tens of GB and can contain more than 100k files. Raw folder transfer to iPhone can be slow because the bottleneck may be the transfer method, file count, iOS file handling, iCloud sync, or cable speed.

The project itself does not upload archive data. iCloud Drive, AirDrop, Finder, Files, external-drive, or third-party provider transfers are user-managed.

The current architecture is best tested incrementally:

- database-only transfer for chat list, message loading, and full-history pagination;
- small media subsets for media path discovery and future rendering work;
- full raw archive transfer only when the complete media set is required.

Packaged archive import is a likely future design direction. One archive file could be imported by the app, unpacked or indexed locally, and avoid pushing thousands of individual files through app document sharing. That workflow is not implemented yet.

## Future Work

- Experiment with packaged archive import.
- Render images without loading whole archives into memory.
- Add video and audio playback.
- Enrich sender/contact labels from `ContactsV2.sqlite`.
- Add persistent archive bookmarks and polished import management.
- Add synthetic public fixtures for repeatable tests without private data.
