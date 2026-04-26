# iOS WhatsApp Archiver

iOS WhatsApp Archiver is a local, read-only iPhone WhatsApp backup extractor and archive viewer for your own extracted iPhone backups. It is not affiliated with WhatsApp or Meta.

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
- Latest 500 messages per selected chat only; no pagination UI yet.

## Repository Layout

```text
apps/ios-archive-viewer/    SwiftUI iOS archive viewer
tools/                      Local iPhone backup and HTML export tools
docs/                       Design notes and roadmap
test-fixtures/              Public fixture policy
```

## Privacy Warning

Never commit extracted backups, WhatsApp databases, media folders, generated exports, or private chat data. In particular, do not commit `ChatStorage.sqlite`, `ContactsV2.sqlite`, `Media/`, `Message/`, `data/`, `exports/`, or generated HTML files.

## Acknowledgement

This project was initially prototyped in a fork of `andreas-mausch/whatsapp-viewer`, an MIT-licensed Android WhatsApp database viewer. The current project is a separate iPhone backup extractor and SwiftUI archive viewer.

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
