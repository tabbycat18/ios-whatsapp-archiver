# iOS WhatsApp Archiver

A local, read-only iPhone WhatsApp archive extractor and viewer.

This project is not affiliated with WhatsApp, Meta, or Apple.

## What It Does

- Extracts WhatsApp data from your own local iPhone backup using a local script.
- Opens the extracted archive in a SwiftUI iPhone/iPad viewer.
- Lets you browse chats and available media locally.
- Includes a synthetic demo archive for testing.

## Current Status

- Pre-release and under active development.
- Text browsing, media browsing, archive slots, and the bundled demo archive are
  implemented.
- Installation currently requires an Xcode/developer workflow unless another
  distribution path is added later.
- Some edge cases remain, especially around private WhatsApp schema details,
  contact identity history, very large archives, and unsupported media types.

See [Status and capabilities](docs/status.md) for the full feature list,
limitations, completed milestones, and known issues.

## Quick Start

1. Create an encrypted local iPhone backup in Finder.
2. Run the extractor:

   ```bash
   python3 tools/extract_ios_whatsapp_backup.py \
     "<path-to-ios-backup-folder>" \
     "data/iphone-whatsapp-export"
   ```

3. Build and run the viewer from Xcode:

   ```bash
   open apps/ios-archive-viewer/WhatsAppArchiveViewer.xcodeproj
   ```

4. Add the extracted folder that contains `ChatStorage.sqlite`.
5. Browse chats and available media locally.

For detailed steps, transfer notes, and troubleshooting, read the
[user guide](docs/user-guide.md) and
[iPhone backup extraction guide](docs/iphone-backup-extraction.md).

## Demo Archive

The app bundles a fully synthetic demo archive for testing. It contains no real
WhatsApp data, real phone numbers, private messages, private media, or private
screenshots.

From the archive home screen, tap `Try Demo Archive`. Developers can also open
the fixture manually from:

```text
test-fixtures/demo-archive/
```

See the [demo archive README](test-fixtures/demo-archive/README.md) for fixture
coverage and regeneration notes. Any screenshots used for demos or docs should
come from this synthetic archive, not private chats.

## Privacy

- Local-only: this project has no server.
- No cloud upload is performed by this project.
- The extractor reads a local iPhone backup and writes a local extracted archive.
- The viewer opens local archive files read-only.
- Do not commit private archives, WhatsApp databases, media folders, generated
  exports, screenshots from private chats, or copied backup data.
- Third-party transfer services are optional and user-managed.

For more detail, see [Privacy](PRIVACY.md), [Security](SECURITY.md), and the
privacy section in the [user guide](docs/user-guide.md#privacy-and-safety).

## Documentation

- [Full user guide](docs/user-guide.md)
- [iPhone backup extraction](docs/iphone-backup-extraction.md)
- [Status and capabilities](docs/status.md)
- [Roadmap](docs/roadmap.md)
- [Large archive transfer experiments](docs/transfer-experiments.md)
- [Development notes](docs/development.md)
- [Archive format](docs/archive-format.md)
- [Architecture](docs/architecture.md)
- [iOS viewer notes](apps/ios-archive-viewer/README.md)
- [Privacy](PRIVACY.md)
- [Security](SECURITY.md)

## Repository Layout

```text
apps/ios-archive-viewer/    SwiftUI archive viewer
tools/                      Local backup extraction and export tools
docs/                       User, status, architecture, and format notes
test-fixtures/              Synthetic fixture policy and demo archive
```

## Acknowledgement

This project was initially prototyped in a fork of
`andreas-mausch/whatsapp-viewer`, an MIT-licensed Android WhatsApp database
viewer. The current project is a separate iPhone backup extractor and SwiftUI
archive viewer.
