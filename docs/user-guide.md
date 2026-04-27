# User Guide

[Back to README](../README.md)

This guide covers the normal workflow for creating a local iPhone WhatsApp
archive, opening it in the viewer, using the synthetic demo archive, and moving
large archives between devices.

## Requirements

- A Mac with access to the iPhone backup.
- A local iPhone backup that you own or are authorized to inspect.
- Xcode for the current viewer installation workflow.
- Python 3 for the extractor.
- The optional `iphone-backup-decrypt` Python package for encrypted backups.

Current installation is developer/Xcode-oriented. The source is on GitHub, but
this repository does not currently provide a one-tap iPhone install path,
TestFlight distribution, or App Store distribution.

## 1. Create an Encrypted Local iPhone Backup

1. Connect your iPhone to your Mac.
2. Open Finder and select the iPhone in the sidebar.
3. Choose "Back up all of the data on your iPhone to this Mac".
4. Enable "Encrypt local backup".
5. Set and store the backup password somewhere safe.
6. Click "Back Up Now".

Encrypted local backups are recommended because WhatsApp data is stored inside
the encrypted backup. The extractor can prompt for the password locally if
`--password` is omitted.

## 2. Extract WhatsApp Files

Run the extractor from the repository root:

```bash
python3 tools/extract_ios_whatsapp_backup.py \
  "<path-to-ios-backup-folder>" \
  "data/iphone-whatsapp-export"
```

The output should stay under ignored local folders such as `data/` or
`exports/`. Do not move private archives into tracked repository folders.

For dependency notes, expected output structure, and troubleshooting, see the
[iPhone backup extraction guide](iphone-backup-extraction.md).

## 3. Build and Open the Viewer

Open the Xcode project:

```bash
open apps/ios-archive-viewer/WhatsAppArchiveViewer.xcodeproj
```

Build and run with full Xcode on an iOS simulator or device. Command Line Tools
alone are not enough for simulator builds.

The current app can open archives through its archive library and Files picker.
It does not currently provide a packaged non-Xcode install path.

## 4. Add an Archive

From the archive home screen:

1. Choose the WhatsApp or WhatsApp Business slot.
2. Add the extracted folder that contains `ChatStorage.sqlite`.
3. Prefer selecting the folder over selecting `ChatStorage.sqlite` directly.
4. Browse chats and available media.

Selecting the folder is preferred because media availability checks, document
preview, audio/video playback, profile/avatar lookup, and wallpaper lookup use
the archive root.

The viewer saves a local archive record with bookmark metadata and a local
label. Removing that saved record does not delete archive files. If an external
archive folder is moved or iOS marks the saved access stale, relink it from the
archive slot.

## 5. Browse Chats and Media

The viewer opens the database read-only and loads messages for the selected
chat. Large chats start with the latest messages and load older history as you
scroll upward.

Available local photos, videos, audio, voice messages, and common documents are
shown in the chat when the archive contains resolvable files. Missing or
unsupported media remains as a placeholder. The Chat Info screen provides a
lightweight per-chat media view for previewable media, photos, videos, and
documents.

The app can optionally use iPhone Contacts to improve names for phone-based
archived participants. Contacts access is local, read-only, and enabled only
after the user chooses it from the app.

For the detailed capability and limitation list, see
[Status and capabilities](status.md).

## Demo Archive

The app bundles a public synthetic fixture at:

```text
test-fixtures/demo-archive/
```

Tap `Try Demo Archive` on the archive home screen to open it. The demo is
labeled `Demo Archive`, does not use either real archive slot, and is not saved
as a user archive record.

Developers can also test the manual Add flow by selecting
`test-fixtures/demo-archive/` through a real archive slot. The same folder can
work on device if it is copied through Finder or Files and then selected in the
app.

The fixture contains no real WhatsApp data, real phone numbers, private
messages, private media, or private screenshots. Screenshots for demos or docs
should come from the synthetic demo archive.

See [Synthetic Demo WhatsApp Archive](../test-fixtures/demo-archive/README.md)
for feature coverage and regeneration notes.

## Transfer Notes

Real extracted WhatsApp archives can be tens of GB and can contain more than
100k files. Raw folder transfer to iPhone can be slow even with modern devices.
The bottleneck can be the transfer method, number of files, iOS file handling,
iCloud sync, or cable speed.

Recommended current workflow:

1. Validate the archive locally with `ChatStorage.sqlite` first.
2. Transfer only `ChatStorage.sqlite` and sidecars if text browsing is enough.
3. Use a small media subset when testing media rendering changes.
4. Transfer the full raw media archive only when the full media set is needed.

Transfer options:

- Raw folder transfer through Files, iCloud Drive, AirDrop, or another provider
  can work, but it may be slow for very large archives.
- iCloud Drive is optional and user-managed. Copy/paste is safer than drag/drop
  if you want to keep the original Mac copy.
- Large folders may appear in iCloud Drive locally before cloud sync has
  finished. Wait for upload/sync completion, then ensure the folder is
  downloaded locally on iPhone before opening it.
- AirDrop can work, but very large transfers may be slow and iPhone may need
  additional time to save received data.
- Zip/package transfer is an experiment, not current app support. The app does
  not open zip files directly; unpack the archive first and select the folder
  containing `ChatStorage.sqlite`.
- Third-party transfer services are optional and user-managed. Uploading a
  WhatsApp archive to such a service changes the privacy model.

See [Large archive transfer experiments](transfer-experiments.md) for detailed
transfer caveats and measurement notes.

## Privacy and Safety

- This project has no server and does not upload archive data.
- Keep local archives under ignored folders such as `data/` or `exports/`.
- Do not commit extracted archives, WhatsApp databases, media folders, generated
  exports, screenshots from private chats, or copied backup data.
- Saved archive records are local bookmark metadata only.
- iPhone Contacts matching is optional, local, read-only, and in memory for the
  app session.
- Third-party transfer services are optional and user-managed.
- Run `git status --short --ignored` before commits to check for private local
  data.

More project-level notes are in [Privacy](../PRIVACY.md) and
[Security](../SECURITY.md).

## Troubleshooting

- `Missing Manifest.db` or `Missing Manifest.plist`: the backup argument is not
  the actual iPhone backup folder.
- `Missing iphone-backup-decrypt`: install the optional dependency in the Python
  environment used to run the extractor.
- Password prompt fails or decryption fails: confirm the encrypted local backup
  password.
- No files matched the default domain: confirm WhatsApp is installed in that
  backup.
- Viewer cannot find `ChatStorage.sqlite`: select the extracted shared-container
  folder, not the parent output folder.
- Media placeholders show unavailable files: make sure the extracted archive
  folder, including `Media/` and `Message/`, was transferred and downloaded
  locally.
- Zip file does not open in the viewer: unzip it first. Direct zip import is not
  implemented.
