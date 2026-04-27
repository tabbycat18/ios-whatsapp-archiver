# WA Archiver

WA Archiver is a free and open-source tool for reading an extracted iPhone
WhatsApp archive locally. It has two parts:

- a local Python extractor that reads your own encrypted iPhone backup on a Mac;
- a native SwiftUI iPhone/iPad viewer that opens the extracted archive folder.

The project is pre-release, but the current app can browse chats, load message
history incrementally, show available local media, and open a bundled synthetic
demo archive.

WA Archiver is an independent open-source project and is not affiliated with,
endorsed by, or sponsored by WhatsApp LLC or Meta Platforms, Inc. WhatsApp is a
trademark of its respective owner.

## What It Does

- Extracts WhatsApp shared-container files from a local iPhone backup.
- Opens an extracted archive folder containing `ChatStorage.sqlite`.
- Reads the archive in place with read-only SQLite access.
- Browses chats, text messages, available photos, videos, audio, and documents.
- Remembers local archive shortcuts without copying or uploading archive data.
- Includes a small synthetic demo archive for screenshots, testing, and public
  examples.

## Privacy Model

WA Archiver is local-first by design:

- No server is included in this project.
- No archive upload is performed by this project.
- The extractor reads local backup files and writes a local extracted archive.
- The iOS viewer opens selected archive files read-only.
- Saved archive records are local bookmark metadata, not copied chat content.
- Optional iPhone Contacts matching is local, read-only, and user initiated.

Your archive can contain private messages, contacts, account metadata, photos,
videos, documents, and other sensitive files. Keep real archives under ignored
local folders such as `data/` or `exports/`, and never commit private WhatsApp
databases, media, generated exports, private screenshots, or iPhone backups.

See [Privacy](PRIVACY.md), [Security](SECURITY.md), and the
[user guide privacy notes](docs/user-guide.md#privacy-and-safety).

## Current Status

This is an early public project for technical users and testers. It is useful
today if you are comfortable with Xcode and local backup extraction, but it is
not yet a polished one-tap consumer install.

Implemented highlights include:

- local iPhone backup extraction;
- native iOS archive viewer;
- saved archive slots for WhatsApp and WhatsApp Business;
- chat list and message browsing;
- incremental loading for large chats;
- conservative status/story separation;
- lazy local media rendering;
- optional local iPhone Contacts matching;
- bundled offline Help / Instructions screen;
- bundled synthetic demo archive.

See [Status and capabilities](docs/status.md) for the detailed feature list,
known issues, and current behavior.

## Installation Status

The current install path is an Xcode/developer install:

```bash
open apps/ios-archive-viewer/WhatsAppArchiveViewer.xcodeproj
```

Build and run the app from Xcode on an iPhone, iPad, or simulator. Full Xcode is
required for normal iOS builds; Command Line Tools alone are not enough for
simulator/device builds.

There is no public TestFlight or App Store build yet. TestFlight/App Store
distribution requires Apple Developer Program membership, signing, App Store
Connect setup, review steps, and ongoing maintenance. Free Apple Account
installs from Xcode can expire after 7 days and may need to be reinstalled from
Xcode when the provisioning profile expires.

GitHub is not a one-tap iPhone installation path. A random GitHub-hosted `.ipa`
is not enough for most users because iOS still requires valid signing,
provisioning, and an Apple-supported distribution path.

See [installation and distribution](docs/distribution.md) for the longer
breakdown.

## Basic Archive Workflow

1. Create an encrypted local iPhone backup on your Mac with Finder.
2. Run the extractor from this repository:

   ```bash
   python3 tools/extract_ios_whatsapp_backup.py \
     "<path-to-ios-backup-folder>" \
     "data/iphone-whatsapp-export"
   ```

3. Transfer the extracted archive folder to your iPhone using Files, iCloud
   Drive, AirDrop, Finder, or another user-managed local workflow.
4. Open WA Archiver and add the extracted folder that contains
   `ChatStorage.sqlite`.

Selecting the whole archive folder is preferred over selecting only
`ChatStorage.sqlite` because media availability, previews, wallpaper lookup,
and profile/avatar lookup use the archive root.

Detailed extraction and transfer notes are in the
[iPhone backup extraction guide](docs/iphone-backup-extraction.md) and
[user guide](docs/user-guide.md).

## Demo Archive

The app bundles a fully synthetic demo archive:

```text
test-fixtures/demo-archive/
```

From the archive home screen, tap `Try Demo Archive`. The demo contains no real
WhatsApp data, no real phone numbers, no private messages, no private media,
and no private screenshots. Public screenshots and docs should use this demo
fixture, not private chats.

See the [demo archive README](test-fixtures/demo-archive/README.md) for fixture
coverage and regeneration notes.

## Screenshots

No public screenshots are committed yet. When screenshots are added, they should
come only from the synthetic demo archive and can be placed here:

- Archive home
- Chat list
- Message view
- Demo media view

Do not use screenshots from real chats or real archives.

## Known Limitations

- Current installation requires Xcode or developer/test distribution.
- No public TestFlight or App Store build is available yet.
- Free Apple Account installs from Xcode can expire after 7 days.
- Direct zip/package import is not implemented.
- Very large raw archive folder transfers can be slow.
- Media support is best effort and lazy; unsupported or missing files stay as
  placeholders.
- WhatsApp private database schema details are not fully mapped.
- `@lid` identifiers and uncertain contact mappings remain conservative.

## Roadmap

Near-term work:

- Continue validating private schema mappings with synthetic/public fixtures.
- Improve non-developer installation and first-run guidance.
- Add packaged archive import support.
- Expand media browsing and attachment support.
- Improve performance for very large archives.
- Prepare a TestFlight/App Store path when signing, review, and maintenance are
  ready.

See [Roadmap](docs/roadmap.md) for the full project roadmap.

## Optional Support

WA Archiver is free and open-source. Optional support helps pay for the Apple
Developer Program so the app can eventually be published on TestFlight/App
Store, and helps with future maintenance.

No paid features. No locked content.

<!-- TODO: Add the maintainer's Buy Me a Coffee/support URL before public sharing if donations should be linked from the README. -->

## Documentation

- [Full user guide](docs/user-guide.md)
- [iPhone backup extraction](docs/iphone-backup-extraction.md)
- [Installation and distribution](docs/distribution.md)
- [Status and capabilities](docs/status.md)
- [Roadmap](docs/roadmap.md)
- [Release checklist](docs/release-checklist.md)
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

## Security Warning

Before committing or sharing anything from this repository, check that you are
not including real WhatsApp archives or private backups. Do not stage or commit
`data/`, `exports/`, `ChatStorage.sqlite*`, `ContactsV2.sqlite*`, `Media/`,
`Message/`, generated HTML exports, copied iPhone backups, or screenshots from
private chats. The synthetic fixture under `test-fixtures/demo-archive/` is the
only allowed demo archive data.

## Acknowledgement

This project was initially prototyped in a fork of
`andreas-mausch/whatsapp-viewer`, an MIT-licensed Android WhatsApp database
viewer. The current project is a separate iPhone backup extractor and SwiftUI
archive viewer.
