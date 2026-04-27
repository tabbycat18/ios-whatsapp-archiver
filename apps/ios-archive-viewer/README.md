# WA Archiver iOS Viewer

This is a native SwiftUI iPhone and iPad app for local, read-only inspection of
an extracted iOS WhatsApp archive. It is part of
[WA Archiver](../../README.md).

WA Archiver is an independent open-source project and is not affiliated with,
endorsed by, or sponsored by WhatsApp LLC or Meta Platforms, Inc. WhatsApp is a
trademark of its respective owner.

Private WhatsApp data must not be committed. Keep `ChatStorage.sqlite`,
`ContactsV2.sqlite`, `Media/`, `Message/`, generated exports, and private
screenshots under ignored local data folders.

## Open in Xcode

Open the project from the repository root:

```bash
open apps/ios-archive-viewer/WhatsAppArchiveViewer.xcodeproj
```

Build and run with full Xcode on an iOS simulator or device. Command Line Tools
alone are not enough for simulator builds.

The current install path is developer/Xcode-oriented. GitHub source is not a
universal one-tap iPhone install path. Hosting an `.ipa` on GitHub or another
website would not by itself make it installable for most users; iOS still
requires valid signing/provisioning and an Apple-supported distribution path.
This repository does not currently provide TestFlight or App Store
distribution.

For the full install-path breakdown, see
[installation and distribution](../../docs/distribution.md).

## What the App Opens

- An extracted archive folder containing `ChatStorage.sqlite`.
- `ChatStorage.sqlite` directly for database-only testing.
- A bundled, fully synthetic demo archive from the archive home screen.

Selecting the folder is preferred over selecting `ChatStorage.sqlite` directly
because media availability checks, document preview, audio/video playback,
profile/avatar lookup, and wallpaper lookup use the archive root.

The app opens SQLite read-only, sets `PRAGMA query_only = ON`, and stores only
local bookmark metadata for saved archive records. Removing a saved archive
record does not delete archive files.

## Demo Archive

The app target bundles the public synthetic fixture at:

```text
test-fixtures/demo-archive/
```

Tap `Try Demo Archive` on the archive home screen to open it. The demo is
clearly labeled `Demo Archive`, does not occupy either real archive slot, and
does not create a saved archive record.

Developers can regenerate the fixture from the repository root:

```bash
python3 tools/generate_demo_archive.py
```

The fixture contains no real WhatsApp data. Screenshots for demos or docs should
come from the synthetic demo archive, not private chats.

## In-App Help

The archive home screen includes a `How It Works` card and a Help toolbar
button. The instructions screen is bundled in SwiftUI and works offline. It
covers backup creation, extraction, transfer, archive adding, demo usage,
privacy, optional project support, trademark/affiliation notes, and current
installation status without loading remote GitHub docs.

The optional support row is intentionally low pressure and appears only in the
Help / Instructions sheet, not in the main archive import or browsing flow. No
features are paid, gated, or unlocked through support.

## Development Notes

For simulator development, a local development copy of `ChatStorage.sqlite` can
be placed in the app container's Documents folder as:

```text
Documents/ChatStorage.sqlite
```

If sidecar files are present, copy them next to it too:

```text
Documents/ChatStorage.sqlite-wal
Documents/ChatStorage.sqlite-shm
Documents/ChatStorage.sqlite-journal
```

Avoid repeatedly transferring a full real archive during development. Start with
the database and sidecars, then add a small synthetic or private local media
subset only when media behavior is being tested.

## More Detail

- [Root README](../../README.md)
- [User guide](../../docs/user-guide.md)
- [Status and capabilities](../../docs/status.md)
- [Development notes](../../docs/development.md)
- [Archive format](../../docs/archive-format.md)
- [Architecture](../../docs/architecture.md)
- [Roadmap](../../docs/roadmap.md)
- [Transfer experiments](../../docs/transfer-experiments.md)
- [Demo archive](../../test-fixtures/demo-archive/README.md)
