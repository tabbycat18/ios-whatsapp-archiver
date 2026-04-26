# Large Archive Transfer Experiments

This document compares ways to move an extracted iPhone WhatsApp archive from a
Mac to an iPhone.

The current app does not directly open or import zip, tar, or other packaged
archive files. To test a packaged archive today, transfer the package, unpack it,
then select the extracted folder that contains `ChatStorage.sqlite` in the app.

## Privacy First

WhatsApp archives can contain highly sensitive personal data and data from other
people. Local-only transfer remains the privacy-preserving default.

This project does not upload data anywhere. Any iCloud Drive, AirDrop,
SwissTransfer, external-drive, or third-party transfer workflow is optional and
user-managed.

Uploading a WhatsApp archive to a third-party transfer service changes the
privacy model. Use that kind of service only if you understand and accept the
risk for your data. Prefer private or password-protected transfer options where
available, and never commit, share, or publicly upload archives.

## Why Transfer Is Hard

A full iPhone WhatsApp archive can be 36-40 GB or larger and contain more than
130k files. Moving a raw folder can be slow because the transfer path has to
handle every individual file, not just the total byte count.

Packaged transfer may reduce many-small-file overhead by moving one large file.
It may not reduce total size much because WhatsApp photos, videos, and voice
notes are usually already compressed.

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

## Transfer Methods

### A. Raw Folder AirDrop

Raw folder AirDrop can work, but it can be slow for a 36-40 GB archive with
130k+ files. The iPhone may also spend a long time saving the received folder
after the visible transfer progress appears complete.

Use this when you want a local-only Apple transfer path and are willing to wait.

### B. iCloud Drive

iCloud Drive is optional and user-managed. Copy/paste the archive folder if you
want to keep the local Mac copy; dragging can move or copy depending on source
and destination.

Large folders may appear locally before upload or sync has finished. Wait for
sync to complete on the Mac, then ensure the folder is downloaded locally on the
iPhone before opening it in the viewer.

### C. Zip Or Package Transfer

A zip or tar package is one large file, which can avoid some many-small-file
overhead. It may not reduce size much because most WhatsApp media is already
compressed.

Packaging requires extra free space on the Mac. Downloading and unpacking
requires extra free space on the iPhone or on whichever device performs the
unpack step.

The current app does not open zip files directly. Unzip first, then select the
unpacked folder containing `ChatStorage.sqlite`.

Example store-only zip command:

```bash
mkdir -p exports/transfer-tests

/usr/bin/time -p bash -lc '
  cd data &&
  zip -r -0 -X ../exports/transfer-tests/iphone-whatsapp-export-store.zip iphone-whatsapp-export
'
```

Keep generated packages in ignored folders such as `exports/` or `data/`.

### D. SwissTransfer Or Similar Large-File Service

SwissTransfer or a similar large-file transfer service can be useful for people
with fast upload and download connections. This is optional and user-managed; it
is not part of this project and is not controlled by this project.

Local test note: a roughly 40 GB zip uploaded to SwissTransfer in under about 10
minutes on a high-speed fiber connection. A download on a fast connection may
also be faster than raw AirDrop, but it depends on internet speed, iPhone
storage, Wi-Fi, browser behavior, and service conditions.

SwissTransfer currently advertises large file transfers up to 50 GB and
temporary availability. Check the service's current terms, limits, expiry
settings, and privacy settings yourself before using it:
<https://www.infomaniak.com/en/support/faq/2451/getting-started-swisstransfer>

Privacy warning: this uploads the archive to a third-party service. Use only if
that is acceptable for your archive. Prefer password-protected or private
transfer options where available.

## What To Measure

Run each experiment against the same extracted archive whenever possible. Record
the archive size and file count before testing transfer methods.

Useful Mac commands:

```bash
du -sh "data/iphone-whatsapp-export"
find "data/iphone-whatsapp-export" -type f | wc -l
```

Keep detailed command output out of git if it contains private paths or
filenames.

## Results Template

| Method | Input | Size | File count | Packaging time | Upload/transfer time | iPhone save/download time | Unzip time | Viewer opened? | Notes |
| --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- |
| Raw folder AirDrop | Extracted folder |  |  | N/A |  |  | N/A | Yes/No |  |
| iCloud Drive | Extracted folder |  |  | N/A |  |  | N/A | Yes/No |  |
| Zip/package transfer | zip/tar |  |  |  |  |  |  | Yes/No |  |
| SwissTransfer or similar | zip/tar |  |  |  |  |  |  | Yes/No |  |

## Local Test Notes

These are local observations from one large private archive. They are not a
promise of performance on other networks, devices, or services.

| Method | Input | Size | File count | Packaging time | Upload/transfer time | iPhone save/download time | Unzip time | Viewer opened? | Notes |
| --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- |
| Raw folder AirDrop | Extracted folder | 36-40 GB | 130k+ | N/A | Around an hour or more including transfer/save | Included in transfer/save observation | N/A | Yes | Succeeded, but very slow. |
| Store-only zip creation | Extracted folder | 36 GB archive, 36 GB zip | 131719 | 195.82 seconds | N/A | N/A | Pending | Pending | Zip completed; size stayed close to archive size. |
| SwissTransfer upload | Store-only zip | About 40 GB | N/A | Completed before upload | Under about 10 minutes on fiber | Pending | Pending | Pending | Download, unzip, and viewer result still need testing. |

## Interpreting Results

- If raw folder transfer is slow but package transfer is faster, file-count
  overhead is likely a major factor.
- If package size is close to archive size, compression is not the main benefit.
- If unzip time or iPhone free-space requirements dominate the workflow, direct
  packaged import may still need careful design before it is useful.
- If the viewer opens the unpacked result, the transfer preserved the archive
  structure needed by the current app.
