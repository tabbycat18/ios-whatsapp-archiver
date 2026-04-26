# WhatsApp Archiver

WhatsApp Archiver is a local extractor and read-only archive viewer for
your own iPhone WhatsApp backup.

This project is not affiliated with WhatsApp, Meta, or Apple.

## What It Does

This project helps you:

1. make an encrypted local iPhone backup on your Mac,
2. extract WhatsApp files from that backup,
3. open the extracted archive in a read-only SwiftUI viewer.

The app is currently a development tool. Xcode is required to build and install
the viewer.

## Privacy Summary

- There is no server in this project.
- This project does not upload data to any cloud service.
- The extractor reads a local iPhone backup and writes a local extracted archive.
- The viewer opens local SQLite files read-only.
- The viewer can remember selected local archives using app-local bookmark metadata.
- Removing a saved archive from the viewer does not delete the archive files.
- Any iCloud Drive, AirDrop, SwissTransfer, external-drive, or other transfer
  workflow is optional and user-managed.

WhatsApp archives can contain highly sensitive messages, contacts, photos,
videos, audio, and data from other people. Never commit extracted backups,
WhatsApp databases, media folders, generated exports, or private chat data.

## Current Status

Working now:

- Extract WhatsApp shared-container files from a local iPhone backup.
- Open an extracted archive folder or `ChatStorage.sqlite`.
- Try a bundled, fully synthetic demo archive from the archive home screen.
- Read offline in-app instructions from the archive home screen.
- Remember selected archives locally so they can be reopened without selecting the folder again.
- Manage two local saved archive slots: WhatsApp and WhatsApp Business.
- Browse chats and text messages.
- Show local profile pictures in the chat list when profile/avatar cache files are present in the selected archive.
- Search chat titles in the loaded chat list.
- Read large chats incrementally by scrolling upward to load older messages.
- Render available photo attachments inline.
- Open available video attachments in a tap-to-play video preview.
- Play available audio and voice attachments with a simple play/pause control and share them from the chat row.
- Show PDF and common document attachments as document rows, with local preview and sharing when the file resolves.
- Show captions/text attached to photo, video, audio, or document rows under the media in the same bubble.
- Use the extracted WhatsApp chat wallpaper as the message background when `current_wallpaper.jpg` is present at the archive root.
- Detect WhatsApp Status/Stories rows only from reliable message/session evidence such as `status@broadcast`, and keep them out of normal direct-chat browsing.
- Show a lightweight Chat Info screen with per-chat filters for all previewable chat media, photos, videos, and documents, with available local media prioritized and selectable for grouped sharing/export; voice-message audio stays in chat rows instead of the media grid.
- Share photos and videos from their local preview sheets without uploading them.
- Keep missing or unsupported media as placeholders.
- Show conservative system/call placeholders without exposing raw sender IDs.
- Use `ContactsV2.sqlite` when available for conservative contact-name and split-session resolution.
- Keep real duplicate-title conversations separate while hiding technical system-only or no-visible-message archive fragments from normal browsing.
- Detect whether referenced media files appear available in the selected archive.

Not implemented yet:

- Full per-chat media library browsing beyond the first lightweight filtered view.
- Complete `ContactsV2.sqlite` enrichment for every historical contact edge case.
- Direct zip/package import.
- Non-Xcode installation or distribution.

For zip or packaged archives, unpack the archive first, then select the
extracted folder containing `ChatStorage.sqlite`.

## Quick Start

1. Create a local iPhone backup in Finder with "Encrypt local backup" enabled.
2. Run the extractor:

   ```bash
   python3 tools/extract_ios_whatsapp_backup.py \
     "<path-to-ios-backup-folder>" \
     "data/iphone-whatsapp-export"
   ```

   For encrypted backups, the script prompts for the backup password if
   `--password` is omitted.

3. Open the viewer project in Xcode:

   ```bash
   open apps/ios-archive-viewer/WhatsAppArchiveViewer.xcodeproj
   ```

4. Build and run the app, then choose the WhatsApp or WhatsApp Business slot
   and add either:
   - the extracted folder containing `ChatStorage.sqlite`, or
   - `ChatStorage.sqlite` directly.

   The viewer saves a local archive record with a local label so the archive
   can be reopened later without selecting it again. Removing a saved archive
   record does not delete files. If an external folder is moved or iOS marks
   the saved file access stale, relink it from the archive slot.

5. For large iPhone transfers, read the transfer guide before copying the full
   archive.

## Demo Archive

The app target bundles the public synthetic fixture from
`test-fixtures/demo-archive/`. On the archive home screen, tap
`Try Demo Archive` to open it without choosing files. The demo is labeled
`Demo Archive`, does not use either real archive slot, and is not saved as a
user archive record.

Developers can also manually open the same fixture by adding a real archive
slot and selecting:

```text
test-fixtures/demo-archive/
```

Selecting the folder is preferred over selecting `ChatStorage.sqlite` directly
because media availability checks and wallpaper lookup use the archive root.
Regenerate the fixture with:

```bash
python3 tools/generate_demo_archive.py
```

The fixture is fully synthetic and must remain under `test-fixtures/`. Normal
non-Xcode distribution is still future work; this repository does not currently
provide a one-tap iPhone install path from GitHub.

## In-App Help

The archive home screen includes a `How It Works` card and a Help toolbar
button. The instructions are bundled in the app and work offline. They explain
the backup, extraction, transfer, archive adding, demo archive, privacy, and
current installation status without linking to remote GitHub docs.

Current installation still requires Xcode or another developer/test
distribution path. Future distribution options may include TestFlight, App
Store, EU alternative distribution, or Web Distribution if requirements are met.

## Documentation

- [iPhone backup extraction](docs/iphone-backup-extraction.md)
- [Large archive transfer experiments](docs/transfer-experiments.md)
- [Archive format](docs/archive-format.md)
- [Architecture](docs/architecture.md)
- [Roadmap](docs/roadmap.md)
- [Privacy](PRIVACY.md)
- [Security](SECURITY.md)

## Repository Layout

```text
apps/ios-archive-viewer/    SwiftUI iOS archive viewer
tools/                      Local iPhone backup and HTML export tools
docs/                       Architecture, extraction, format, and roadmap notes
test-fixtures/              Public fixture policy
```

## Acknowledgement

This project was initially prototyped in a fork of
`andreas-mausch/whatsapp-viewer`, an MIT-licensed Android WhatsApp database
viewer. The current project is a separate iPhone backup extractor and SwiftUI
archive viewer.
