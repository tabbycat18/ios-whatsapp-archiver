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
- friendly contact or chat title fallback;
- message count;
- latest message date;
- sender direction;
- sanitized sender label;
- safe phone-number fallback for unsaved group senders when it can be extracted from a sender JID without exposing the JID;
- message text;
- message date;
- message and group-event type when available;
- media local path, title, size, URL, vCard, location, and inferred attachment kind when available.

## Ordering and Pagination

Messages are displayed oldest-to-newest. The initial load fetches the latest 500 rows for the selected chat. Older history is loaded incrementally with a keyset cursor made from:

- `ZMESSAGEDATE`
- `Z_PK`

Using the primary key as a tie-breaker keeps pagination stable when multiple messages have the same timestamp.

The chat list prefers the latest relevant user-visible message date for each
chat. Known system-notice message types are excluded from that primary latest
date so notices such as security-code changes do not make a chat appear newer
than the last real conversation row. If no relevant message date is available,
the viewer falls back to the last-message pointer date, then the maximum message
date, then a sanitized `ZWACHATSESSION.ZLASTMESSAGEDATE`.

This approximates WhatsApp ordering but may differ where WhatsApp applies
private ranking or filtering logic not yet mapped by this project.

## Message Classification

The viewer classifies message rows conservatively from available message type,
group-event type, and media metadata:

- photos, videos, audio, documents, contacts, locations, stickers, and link previews are shown as placeholders;
- likely call rows are labeled as calls when the message type evidence supports it;
- known system-notice rows are labeled as system messages;
- deleted rows are labeled as deleted messages when the message type supports it;
- unknown mappings remain generic instead of exposing internal identifiers.

The exact private WhatsApp meaning of every type value is not fully mapped.

## Media State

Media metadata and safe relative path discovery are implemented. The viewer can
show placeholders and determine whether referenced files appear available under
the selected archive root.

Path resolution is archive-root-relative and checks common extracted layouts
such as `Media/` and `Message/Media/`. It does not print full private media
paths by default and does not load media binaries.

Media rendering is not implemented yet. The viewer does not load thumbnails, photos, videos, audio files, or other media binaries into memory.

## Not Yet Used

`ContactsV2.sqlite` is extracted and documented as private data, but it is not used for contact enrichment yet.
