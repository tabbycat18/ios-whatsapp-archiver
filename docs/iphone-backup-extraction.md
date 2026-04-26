# iPhone Backup Extraction

This guide explains how to create a local iPhone backup on macOS and extract the WhatsApp shared-container files used by the SwiftUI archive viewer.

Run the extractor only on backups you own or are authorized to inspect. Extracted output can contain private messages, contacts, account metadata, and media references. Keep output under ignored local folders such as `data/` or `exports/`.

## 1. Create a Local iPhone Backup

1. Connect your iPhone to your Mac.
2. Open Finder and select the iPhone in the sidebar.
3. Choose "Back up all of the data on your iPhone to this Mac".
4. Enable "Encrypt local backup".
5. Set and store the backup password somewhere safe.
6. Click "Back Up Now".

Encrypted local backups are supported. The extractor needs the backup password for encrypted backups because WhatsApp files are stored inside the encrypted iPhone backup.

## 2. Locate the Backup Folder

Finder stores local iPhone backups under the user's MobileSync backup folder. The common macOS location is:

```text
~/Library/Application Support/MobileSync/Backup/
```

That directory can contain multiple backup folders. Use device information and modification dates to identify the backup you just created. The backup folder must contain `Manifest.db` and `Manifest.plist`.

## 3. Extract WhatsApp Files

The extractor CLI is:

```bash
python3 tools/extract_ios_whatsapp_backup.py [-h] [--password PASSWORD] [--domain-like DOMAIN_LIKE] backup output
```

Arguments:

- `backup`: path to the iPhone backup folder containing `Manifest.db` and `Manifest.plist`.
- `output`: output folder for extracted WhatsApp files.
- `--password`: encrypted backup password. If omitted for an encrypted backup, the script prompts locally.
- `--domain-like`: optional manifest domain `LIKE` pattern. The default is `%whatsapp%WhatsApp%.shared`.

### Encrypted Backup With Password Argument

Encrypted extraction requires the optional `iphone-backup-decrypt` package. Install it in your chosen Python environment if the script reports it missing.

```bash
python3 -m pip install iphone-backup-decrypt
python3 tools/extract_ios_whatsapp_backup.py \
  "<path-to-ios-backup-folder>" \
  "data/iphone-whatsapp-export" \
  --password "<backup-password>"
```

### Encrypted Backup With Local Prompt

Omit `--password` to avoid putting the password in shell history. The script will prompt locally.

```bash
python3 tools/extract_ios_whatsapp_backup.py \
  "<path-to-ios-backup-folder>" \
  "data/iphone-whatsapp-export"
```

### Unencrypted Backup

Unencrypted backups use the same positional arguments and do not need `--password`:

```bash
python3 tools/extract_ios_whatsapp_backup.py \
  "<path-to-ios-backup-folder>" \
  "data/iphone-whatsapp-export"
```

## 4. Expected Output Structure

The extractor preserves the iPhone backup manifest domain as a top-level folder. With the default domain pattern, a typical archive looks like:

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

The exact domain folder name can vary by WhatsApp version and backup metadata. Some sidecar files may be absent. The viewer needs the folder that contains `ChatStorage.sqlite`; selecting that folder is preferred over selecting only the database because media availability checks use the folder as the archive root.

## 5. Open in the Viewer

Open the Xcode project:

```bash
open apps/ios-archive-viewer/WhatsAppArchiveViewer.xcodeproj
```

Build and run the app in Xcode. Use Open Archive to select the extracted shared-container folder or `ChatStorage.sqlite` directly.

The app copies `ChatStorage.sqlite` and any SQLite sidecars into its Application Support folder, opens the copied database with read-only SQLite flags, and sets `PRAGMA query_only = ON`. The selected archive root is kept for safe media path resolution. Media rendering is not implemented yet.

## 6. Transfer to iPhone

The current viewer opens archives through the iOS Files picker. App document sharing through Finder is not configured yet.

Recommended transfer path:

1. Copy the extracted shared-container folder into iCloud Drive.
2. Wait until iCloud upload and sync complete on the Mac.
3. On iPhone, open Files and navigate to the folder in iCloud Drive.
4. Ensure the folder is downloaded locally before opening it in the viewer.
5. In the viewer, use Open Archive and select the folder containing `ChatStorage.sqlite`.

For iCloud Drive, copy rather than move the archive if you want to keep the original local copy. Finder drag behavior can move or copy depending on source and destination, so copy/paste is safer when preserving the local folder matters. Large folders can appear copied before iCloud has finished uploading in the background.

iCloud Drive is optional and user-managed. This project does not provide a cloud service.

## Troubleshooting

- `Missing Manifest.db` or `Missing Manifest.plist`: the `backup` argument is not the actual iPhone backup folder.
- `Missing iphone-backup-decrypt`: install the optional dependency in the Python environment used to run the extractor.
- Password prompt fails or decryption fails: confirm the encrypted local backup password.
- No files matched the default domain: confirm WhatsApp is installed in that backup, or inspect the backup manifest with a safe local workflow before changing `--domain-like`.
- Viewer cannot find `ChatStorage.sqlite`: select the extracted shared-container folder, not the parent output folder.
- Media placeholders show unavailable files: make sure the whole extracted archive folder, including `Media/` and `Message/`, was transferred and downloaded locally.

## Privacy Checklist

- Keep extracted output under ignored folders such as `data/` or `exports/`.
- Do not commit `ChatStorage.sqlite*`, `ContactsV2.sqlite*`, `Media/`, `Message/`, generated HTML, screenshots, or copied archives.
- Run `git status --short --ignored` before every commit.
