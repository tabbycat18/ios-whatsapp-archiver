# Packaged Archive Transfer Experiments

This document defines a repeatable test plan for comparing ways to move an
extracted iPhone WhatsApp archive from Mac to iPhone.

The current app does not directly import zip, tar, or other packaged archive
files. To test a packaged archive today, transfer the package, unpack it on the
iPhone or Mac, then select the extracted folder that contains
`ChatStorage.sqlite` in the app.

## Goals

- Compare raw folder transfer with packaged archive transfer.
- Measure how much file-count overhead affects transfer time.
- Measure package creation, transfer, save/download, and unpack time separately.
- Confirm whether the viewer can open the final extracted archive.
- Avoid modifying app behavior during this documentation/testing milestone.

## Safety Rules

- Keep all private archives under ignored local folders such as `data/` or
  `exports/`.
- Do not stage or commit `ChatStorage.sqlite`, `ContactsV2.sqlite`, `Media/`,
  `Message/`, generated exports, package files, or private chat data.
- Do not use real private data in screenshots, logs, issues, or pull requests.
- Record measurements and notes only.

## What To Measure

Run each experiment against the same extracted archive whenever possible. Record
the archive size and file count before testing transfer methods.

Useful Mac commands:

```bash
du -sh "data/iphone-whatsapp-export/AppDomainGroup-group.net.whatsapp.WhatsApp.shared"
find "data/iphone-whatsapp-export/AppDomainGroup-group.net.whatsapp.WhatsApp.shared" -type f | wc -l
```

Adjust paths to match the local archive. Keep command output out of git if it
contains private paths or filenames.

## Free-Space Requirements

Large archives need more free space than the final archive size.

- Raw folder transfer needs enough space for the copied archive at the
  destination.
- iCloud Drive copy/paste may temporarily keep both a local copy and an iCloud
  copy on the Mac, and the iPhone may need additional space while downloading.
- AirDrop raw folder transfer may require extra temporary space while iOS saves
  the received folder.
- Zip or tar testing needs space for both the original archive and the package
  on the Mac.
- Unpacking a package needs space for both the package and the unpacked archive
  until the package can be deleted.
- For a large archive, plan for substantially more than 2x the archive size
  across packaging, transfer, download, and unpack steps.

Packaged transfer may reduce overhead caused by moving many individual files,
because the transfer system handles one large file instead of thousands of small
files. It may not reduce total size much, because WhatsApp photos, videos, and
voice notes are usually already compressed.

## Test Matrix

Test these workflows separately.

### Raw Folder Transfer

1. Start with the extracted archive folder on the Mac.
2. Copy the raw folder through the chosen provider or cable workflow.
3. On iPhone, wait until the folder is fully saved and locally available.
4. Open the viewer and select the copied folder containing `ChatStorage.sqlite`.
5. Record transfer time, any save/download time, and whether the viewer opened
   the archive.

### iCloud Drive Copy/Paste

1. Copy the extracted archive folder into iCloud Drive on the Mac.
2. Wait until Finder reports upload/sync complete.
3. On iPhone, open Files and download the folder locally if needed.
4. Open the viewer and select the downloaded folder containing
   `ChatStorage.sqlite`.
5. Record Mac copy/upload time, iPhone download time, and viewer result.

### AirDrop Raw Folder

1. Start with the extracted archive folder on the Mac.
2. Send the raw folder to the iPhone with AirDrop.
3. Wait until AirDrop transfer and iPhone save processing are complete.
4. Open the viewer and select the saved folder containing `ChatStorage.sqlite`.
5. Record transfer time, post-transfer save time, failures, and viewer result.

### Zip Or Tar Packaged Archive

1. Start with the extracted archive folder on the Mac.
2. Create a package under an ignored folder such as `data/` or `exports/`.
3. Record package size and Mac packaging time.
4. Transfer the package to the iPhone using iCloud Drive, AirDrop, cable, or
   another user-managed method.
5. Record transfer time and iPhone save/download time.
6. Unpack the package before using the viewer.
7. Select the unpacked folder containing `ChatStorage.sqlite` in the viewer.
8. Record unzip/import time and whether the viewer opened the result.

Example package commands:

```bash
time ditto -c -k --sequesterRsrc --keepParent \
  "data/iphone-whatsapp-export/AppDomainGroup-group.net.whatsapp.WhatsApp.shared" \
  "data/transfer-tests/whatsapp-archive.zip"

time tar -cf "data/transfer-tests/whatsapp-archive.tar" \
  -C "data/iphone-whatsapp-export" \
  "AppDomainGroup-group.net.whatsapp.WhatsApp.shared"
```

These packages are experiment artifacts. Keep them ignored and out of git.

## Results Template

| Test date | Archive size | File count | Packaging method | Package size | Mac packaging time | Transfer method | Transfer time | iPhone save/download time | Unzip/import time | Viewer opened result | Notes |
| --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| YYYY-MM-DD |  |  | Raw folder | N/A | N/A |  |  |  | N/A | Yes/No |  |
| YYYY-MM-DD |  |  | iCloud Drive copy/paste | N/A | N/A | iCloud Drive |  |  | N/A | Yes/No |  |
| YYYY-MM-DD |  |  | AirDrop raw folder | N/A | N/A | AirDrop |  |  | N/A | Yes/No |  |
| YYYY-MM-DD |  |  | zip |  |  |  |  |  |  | Yes/No |  |
| YYYY-MM-DD |  |  | tar |  |  |  |  |  |  | Yes/No |  |

## Interpreting Results

- If raw folder transfer is slow but package transfer is faster, file-count
  overhead is likely a major factor.
- If package size is close to archive size, compression is not the main benefit.
- If unzip time or iPhone free-space requirements dominate the workflow, direct
  packaged import may still need careful design before it is useful.
- If the viewer opens the unpacked result, the transfer preserved the archive
  structure needed by the current app.
