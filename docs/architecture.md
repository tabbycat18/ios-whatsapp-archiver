# Architecture

ios-whatsapp-archiver is split into local tools and a native iOS viewer.

## Tools

`tools/extract_ios_whatsapp_backup.py` reads an iPhone backup manifest and extracts WhatsApp shared-container files to a local output folder. Encrypted backup support depends on `iphone-backup-decrypt`.

`tools/export_ios_whatsapp_html.py` is a proof-of-concept local HTML exporter. Generated HTML contains private chat content and must stay out of version control.

## SwiftUI Viewer

The iOS app is isolated under `apps/ios-archive-viewer/`. It opens an extracted `ChatStorage.sqlite`, copies the selected database and SQLite sidecars into app storage, and opens the copied database read-only with `PRAGMA query_only = ON`.

The current viewer loads chat summaries from `ZWACHATSESSION` and the latest 500 messages per selected chat from `ZWAMESSAGE`.
