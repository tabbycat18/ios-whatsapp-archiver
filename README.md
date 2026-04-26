# ios-whatsapp-archiver

ios-whatsapp-archiver is a local, read-only iPhone WhatsApp archive extractor and viewer. It is not affiliated with WhatsApp or Meta.

The project has two parts:

1. iPhone backup extraction tools for extracting WhatsApp files from a local iPhone backup.
2. A native SwiftUI iOS archive viewer for opening an extracted `ChatStorage.sqlite` archive locally.

There is no cloud upload, no server component, and no code path intended to modify the WhatsApp database. The viewer opens SQLite in read-only mode and enables `PRAGMA query_only = ON`.

## Current Validated Status

- A real `ChatStorage.sqlite` opens.
- The chat list loads.
- Large chats open.
- Message dates, ordering, and sender direction are correct.
- The app remains responsive by loading the latest 500 messages per selected chat.

## Current Limitations

- No media rendering yet.
- No voice note, photo, or video display yet.
- No `ContactsV2.sqlite` enrichment yet.
- No polished import persistence yet.
- No pagination UI beyond the latest 500 messages.

## Repository Layout

```text
apps/ios-archive-viewer/    SwiftUI iOS archive viewer
tools/                      Local iPhone backup and HTML export tools
docs/                       Design notes and roadmap
test-fixtures/              Public fixture policy
```

## Privacy Warning

Never commit extracted backups, WhatsApp databases, media folders, or generated exports. In particular, do not commit `ChatStorage.sqlite`, `ContactsV2.sqlite`, `Media/`, `Message/`, `data/`, `exports/`, or generated HTML files.

## Quick Start

Extract WhatsApp files from a local iPhone backup:

```bash
python3 tools/extract_ios_whatsapp_backup.py /path/to/iPhone/Backup exports/whatsapp-extracted
```

Generate a local HTML proof-of-concept export:

```bash
python3 tools/export_ios_whatsapp_html.py --input exports/whatsapp-extracted/AppDomainGroup-group.net.whatsapp.WhatsApp.shared
```

Open the SwiftUI app in Xcode:

```bash
open apps/ios-archive-viewer/WhatsAppArchiveViewer.xcodeproj
```

Use local archives only. Confirm `git status --short --ignored` before committing any development artifacts.
