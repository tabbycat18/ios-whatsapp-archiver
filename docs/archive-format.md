# Archive Format

The validated viewer path focuses on an extracted iOS WhatsApp shared-container archive.

## Extracted Folder

The extractor writes files under the manifest domain folder. A typical shared-container folder is:

```text
AppDomainGroup-group.net.whatsapp.WhatsApp.shared/
```

The viewer should be pointed at the folder that contains `ChatStorage.sqlite`.

Common files and folders:

- `ChatStorage.sqlite`
- `ChatStorage.sqlite-wal`
- `ChatStorage.sqlite-shm`
- `ChatStorage.sqlite-journal`
- `ContactsV2.sqlite`
- `Media/`
- `Message/`

Not every archive has every SQLite sidecar. Media folder layout can vary by WhatsApp version and by what data is present in the backup.

## Current Database Tables

- `ZWACHATSESSION`: chat/session metadata used for chat list rows, message counts, and latest message dates.
- `ZWAMESSAGE`: message rows for the selected chat.
- `ZWAMEDIAITEM`: optional media metadata joined to messages when the table exists and has a message relationship column.

## Current Fields

The viewer uses fields needed for:

- chat title;
- contact JID or identifier fallback;
- message count;
- latest message date;
- sender direction;
- sender label;
- message text;
- message date;
- message type when available;
- media local path, title, size, URL, and inferred attachment kind when available.

## Ordering and Pagination

Messages are displayed oldest-to-newest. The initial load fetches the latest 500 rows for the selected chat. Older history is loaded incrementally with a keyset cursor made from:

- `ZMESSAGEDATE`
- `Z_PK`

Using the primary key as a tie-breaker keeps pagination stable when multiple messages have the same timestamp.

## Media State

Media metadata and safe relative path discovery are implemented. The viewer can show placeholders and determine whether referenced files appear available under the selected archive root.

Media rendering is not implemented yet. The viewer does not load thumbnails, photos, videos, audio files, or other media binaries into memory.

## Not Yet Used

`ContactsV2.sqlite` is extracted and documented as private data, but it is not used for contact enrichment yet.
