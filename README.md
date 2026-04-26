# iOS WhatsApp Archiver

iOS WhatsApp Archiver is a local extractor and read-only SwiftUI archive viewer for your own iPhone WhatsApp backup. The workflow runs on your Mac to extract an iPhone backup, then opens the extracted archive in the iOS viewer.

This project is not affiliated with WhatsApp, Meta, or Apple.

## Privacy Model

- There is no cloud service provided by this project.
- There is no server component.
- The extractor reads a local iPhone backup and writes a local extracted archive.
- The viewer opens SQLite read-only and sets `PRAGMA query_only = ON`.
- The project does not modify the WhatsApp database.
- Data stays local unless you manually copy it somewhere else, such as iCloud Drive.

Never commit extracted backups, WhatsApp databases, media folders, generated exports, or private chat data. In particular, do not commit `ChatStorage.sqlite`, `ContactsV2.sqlite`, `Media/`, `Message/`, `data/`, `exports/`, or generated HTML files.

## Current Status

- Milestone 1: real `ChatStorage.sqlite` browsing validated.
- Milestone 2: media metadata and path discovery is merged on `main` in `46c73eb`.
- Milestone 2.5: full-history pagination is on branch `milestone-2-5-full-history-pagination` and PR `https://github.com/tabbycat18/ios-whatsapp-archiver/pull/new/milestone-2-5-full-history-pagination`.

The old `prototype-media-metadata-discovery` branch was superseded by `46c73eb` and is not required for users.

## Current Capabilities

- Extracts WhatsApp shared-container files from a local iPhone backup.
- Supports encrypted backups when the backup password is available.
- Opens an extracted iPhone WhatsApp archive.
- Reads `ChatStorage.sqlite` read-only.
- Shows the chat list.
- Shows messages for the selected chat.
- Supports full-history access through incremental loading: the viewer opens the latest 500 messages first, then loads older batches on demand.
- Shows media placeholders and detects whether referenced media files appear available in the selected archive.

## Current Limitations

- Photo, video, and audio preview are not implemented yet.
- Media metadata is discovered, but media rendering is future work.
- `ContactsV2.sqlite` enrichment is not implemented yet.
- Import and bookmark persistence are still minimal.
- Large WhatsApp archives require significant local and iPhone storage.
- Full raw archive transfer can be slow for archives with tens of GB and more than 100k files.
- Zip/package import is not implemented yet; packaged archives must be unpacked before selecting them in the app.
- The current SwiftUI app target supports iPhone and iPad; Mac is used for backup extraction and Xcode development.

## Repository Layout

```text
apps/ios-archive-viewer/    SwiftUI iOS archive viewer
tools/                      Local iPhone backup and HTML export tools
docs/                       Architecture, extraction, format, and roadmap notes
test-fixtures/              Public fixture policy
```

## How To Use

### 1. Create a Local iPhone Backup on Mac

1. Connect your iPhone to your Mac.
2. Open Finder and select the iPhone in the sidebar.
3. Choose "Back up all of the data on your iPhone to this Mac".
4. Enable "Encrypt local backup".
5. Set and store the backup password somewhere safe.
6. Click "Back Up Now".

Encrypted backups are supported by the extractor script. The backup password is required to decrypt an encrypted backup.

### 2. Locate the Backup

Finder stores local iPhone backups under the user's MobileSync backup folder. The common macOS location is:

```text
~/Library/Application Support/MobileSync/Backup/
```

That folder can contain multiple device backups. Identify the correct backup folder by device and modification date before extracting.

### 3. Run the Extractor

The extractor CLI is:

```bash
python3 tools/extract_ios_whatsapp_backup.py [-h] [--password PASSWORD] [--domain-like DOMAIN_LIKE] backup output
```

For an encrypted backup, install the optional decrypt dependency if needed, then run:

```bash
python3 -m pip install iphone-backup-decrypt
python3 tools/extract_ios_whatsapp_backup.py \
  "<path-to-ios-backup-folder>" \
  "data/iphone-whatsapp-export" \
  --password "<backup-password>"
```

If you omit `--password` for an encrypted backup, the script prompts locally:

```bash
python3 tools/extract_ios_whatsapp_backup.py \
  "<path-to-ios-backup-folder>" \
  "data/iphone-whatsapp-export"
```

For an unencrypted backup, use the same positional `backup` and `output` arguments and omit `--password`:

```bash
python3 tools/extract_ios_whatsapp_backup.py \
  "<path-to-ios-backup-folder>" \
  "data/iphone-whatsapp-export"
```

The default domain pattern extracts WhatsApp shared-container files matching `%whatsapp%WhatsApp%.shared`. Keep output under ignored local folders such as `data/` or `exports/`.

### 4. Check the Extracted Archive

The extractor preserves the iPhone backup manifest domain as a top-level folder. A typical output looks like:

```text
data/iphone-whatsapp-export/
`-- AppDomainGroup-group.net.whatsapp.WhatsApp.shared/
    |-- ChatStorage.sqlite
    |-- ChatStorage.sqlite-wal
    |-- ChatStorage.sqlite-shm
    |-- ChatStorage.sqlite-journal
    |-- ContactsV2.sqlite
    |-- Media/
    `-- Message/
```

Not every archive has every SQLite sidecar. Use the extracted shared-container folder that contains `ChatStorage.sqlite` as the archive folder for the viewer.

### 5. Run the Viewer

Open the Xcode project:

```bash
open apps/ios-archive-viewer/WhatsAppArchiveViewer.xcodeproj
```

Build and run the app in Xcode on a simulator or device. Use the app's Open Archive action to select either:

- the extracted archive folder that contains `ChatStorage.sqlite`, or
- `ChatStorage.sqlite` directly.

Picking the archive folder is preferred because the app can use that folder as the archive root for media availability checks. The app copies `ChatStorage.sqlite` and SQLite sidecars into its sandbox, opens the copied database read-only, and uses the selected archive root to resolve media paths. Media preview is not implemented yet.

### 6. Transfer an Archive to iPhone

The current app opens archives through the iOS Files picker. App document sharing through Finder is not configured yet.

#### Large Archive Transfer Notes

A full iPhone WhatsApp archive can be tens of GB and can contain more than 100k files. Raw folder transfer can be slow even on modern Mac and iPhone hardware. The bottleneck is often the transfer method, number of files, iOS file handling, iCloud sync, or cable speed, not CPU or SSD speed.

This project does not upload data anywhere. Any iCloud Drive, AirDrop, Finder, Files, external-drive, or third-party provider transfer is user-managed.

#### Recommended Current Workflow

- Extract the backup on the Mac.
- Validate the archive with the viewer using `ChatStorage.sqlite` first.
- For full-history text browsing, transfer only `ChatStorage.sqlite` and its SQLite sidecars if media is not needed.
- For media path or rendering development, use a small media subset first.
- Do not transfer the full archive repeatedly during development.
- Transfer the full archive only when the full media folder is actually needed.
- Prefer testing a packaged archive workflow before repeatedly transferring a raw full folder.

Transfer options:

- Development/testing mode: use only `ChatStorage.sqlite` first, optionally with a small media subset.
- Raw folder transfer: possible through Finder, Files, iCloud Drive, AirDrop, or another provider depending on the workflow, but it can be slow for large archives because it has to handle many individual files.
- Copy the extracted archive folder into iCloud Drive, then open it from Files on the iPhone.
- Copy through another Files provider if it preserves the folder structure and can keep the folder downloaded locally.
- For very large archives, AirDrop or external-drive workflows may be impractical.

For iCloud Drive:

- Copy the archive folder into iCloud Drive rather than moving it if you want to keep the local copy.
- In Finder, dragging may move rather than copy depending on the source and destination; copy/paste is safer when retaining the original matters.
- Large folders may appear to copy quickly while iCloud upload continues in the background.
- Wait until iCloud reports upload and sync complete before relying on the folder from the iPhone.
- On iPhone, open Files, navigate to iCloud Drive, and ensure the archive folder is downloaded locally before opening it in the viewer.

iCloud Drive is an optional user-managed transfer method. It is not part of this project's privacy model.

For AirDrop:

- AirDrop can work, but very large raw archives may transfer slowly.
- The iPhone may spend additional time saving the received data after transfer progress appears mostly complete.

For zip or packaged archive experiments:

- A zip file may transfer more reliably because it is one large file instead of more than 100k small files.
- Zip may not reduce size much because photos and videos are already compressed.
- Creating and unpacking a zip requires extra free space. For a 39 GB archive, expect to need substantially more than 39 GB free during packaging and unpacking.
- The current app does not support opening or importing zip files directly.
- Unzip the archive first, then select the extracted folder containing `ChatStorage.sqlite`.

Future work may add packaged archive import where the app imports one archive file, unpacks or indexes it locally, and avoids transferring thousands of individual files through app document sharing. That is not implemented yet.

## More Documentation

- [iPhone backup extraction](docs/iphone-backup-extraction.md)
- [Archive format](docs/archive-format.md)
- [Architecture](docs/architecture.md)
- [Roadmap](docs/roadmap.md)
- [Privacy](PRIVACY.md)
- [Security](SECURITY.md)

## Acknowledgement

This project was initially prototyped in a fork of `andreas-mausch/whatsapp-viewer`, an MIT-licensed Android WhatsApp database viewer. The current project is a separate iPhone backup extractor and SwiftUI archive viewer.
