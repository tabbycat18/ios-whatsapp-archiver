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
- `current_wallpaper.jpg`
- `current_wallpaper_dark.jpg`
- `Media/`
- `Message/`

Not every archive has every SQLite sidecar. Media folder layout can vary by WhatsApp version and by what data is present in the backup.

## Current Database Tables

- `ZWACHATSESSION`: chat/session metadata used for chat list rows, message counts, and latest message dates.
- `ZWAMESSAGE`: message rows for the selected chat.
- `ZWAMEDIAITEM`: optional media metadata joined to messages when the table exists and has a message relationship column.
- `ContactsV2.sqlite` / `ZWAADDRESSBOOKCONTACT`: optional contact metadata used read-only when present to improve names and connect phone-JID/`@lid` sessions only through unambiguous contact rows.

## Current Fields

The viewer uses fields needed for:

- chat title;
- friendly contact or chat title fallback;
- message count;
- latest message date;
- sender direction;
- sanitized sender label;
- profile push-name fallback from `ZWAPROFILEPUSHNAME` when the sender JID matches a group member;
- safe phone-number fallback for unsaved group senders when it can be extracted from a classic phone-based sender JID without exposing the JID;
- message text;
- message date;
- message and group-event type when available;
- status/story evidence from message/session identifiers such as
  `status@broadcast`;
- media local path, title, size, URL, vCard, location, duration, resolved availability, and inferred attachment kind when available.

The viewer also looks for generic chat wallpaper files at the selected archive
root:

- `current_wallpaper.jpg`
- `current_wallpaper_dark.jpg`

If one is present, it is loaded lazily and used as the message-list background.

## Ordering and Pagination

Messages are displayed oldest-to-newest. The initial load fetches the latest 500 rows for the selected chat. Older history is loaded incrementally with a keyset cursor made from:

- `ZMESSAGEDATE`
- `Z_PK`

Using the primary key as a tie-breaker keeps pagination stable when multiple messages have the same timestamp.

The chat list prefers the latest relevant user-visible message date for each
chat. Relevant rows are currently text rows, media rows, and likely call rows.
Known system-notice message types are excluded from that primary latest date so
notices such as security-code changes do not make a chat appear newer than the
last real conversation row. If no relevant message date is available, visible
uncertain archive entries may fall back to archive activity dates, but
system-only and tiny no-visible-message fragments are hidden from normal
browsing.

This approximates WhatsApp ordering but may differ where WhatsApp applies
private ranking or filtering logic not yet mapped by this project.

## Split Sessions

WhatsApp archives can contain multiple `ZWACHATSESSION` rows that look like the
same visible chat. The viewer merges sessions only when they have strong
identity evidence, such as the exact same non-empty `ZCONTACTJID` or a shared
unambiguous ContactsV2 contact identity. Merged chats query messages across all
related session IDs with the same `(ZMESSAGEDATE, Z_PK)` keyset pagination.

The viewer does not merge by display title alone because unrelated people or
groups can share the same visible title. Same-title sessions are classified
after strong-identity merging:

- sessions with user-visible text, media, or call rows remain visible as
  separate conversations;
- duplicate/system-only sessions are treated as system-only archive fragments;
- tiny sessions with no clear user-visible rows are treated as archive
  fragments;
- uncertain larger entries remain visible with a cautious archive-entry label.

Hidden fragments are omitted from the default chat list and title search. They
are not merged into another chat and their rows are not deleted; they are only
filtered out of normal browsing to avoid technical clutter and misleading recent
dates.

## Status and Stories

WhatsApp Status/Stories media can appear in `ChatStorage.sqlite` as rows that
are not direct messages in a normal chat. The current viewer detects these rows
conservatively using reliable archive evidence, currently `status@broadcast` in
message/session JID fields on non-outgoing rows. Outgoing rows are never hidden
by status/story classification. Path names can be useful diagnostic clues during
an audit, but path-only evidence is not used as runtime product logic because it
can overmatch archive layouts that are not yet validated. The viewer also does
not use recency, such as "last 48 hours", as product logic.

When every row in a session is reliably detected as status/story data, that
session is grouped into a separate Stories / Status section rather than listed
as a normal conversation. Those rows are excluded from normal chat message
loading and from normal chat latest-message dates. Mixed sessions keep direct
messages in the chat while detected status/story rows are kept out of inline
conversation rendering.

Detection remains intentionally narrow. Rows without status/story identifier
evidence are not guessed into this category.

## Message Classification

The viewer classifies message rows conservatively from available message type,
group-event type, and media metadata:

- available photos are rendered inline after downsampling;
- available videos are shown as tap-to-play attachments with lazy thumbnails when thumbnail generation succeeds;
- available audio and voice rows get a simple play/pause control;
- reliably detected status/story media is marked as status/story media and kept
  separate from normal direct-chat rows;
- documents, contacts, locations, stickers, and link previews are shown as placeholders;
- likely call rows are labeled as `VOICE CALL` when the message type evidence supports it;
- known system-notice rows are labeled as system messages;
- deleted rows are labeled as deleted messages when the message type supports it;
- unknown mappings remain generic instead of exposing internal identifiers.

The exact private WhatsApp meaning of every type value is not fully mapped.
`@lid` identifiers are treated as opaque internal identifiers and are not
converted to phone numbers. Unsaved group senders can remain "Unknown sender"
when no friendly name, ContactsV2 name, profile push name, or safe phone-based
JID is available.

ContactsV2 improves contact-name and identity resolution, but it does not prove
that every same-title session belongs to the same real conversation. The viewer
therefore keeps ContactsV2 linking conservative and still applies duplicate-title
fragment classification afterward.

## Media State

Media metadata and safe relative path discovery are implemented. The viewer can
determine whether referenced files appear available under the selected archive
root and keeps a resolved local file URL in memory for available attachments.

Path resolution is archive-root-relative and checks common extracted layouts
such as `Media/` and `Message/Media/`. It does not print full private media
paths by default.

Media rendering is lazy and row-scoped. Photo rows downsample the referenced
image before display. Video rows generate thumbnails only for visible rows and
open playback only after the user taps the attachment. Audio rows create a
player only after the user taps play, and the shared playback controller stops
the previous audio row before starting another.

Photo previews support pinch-to-zoom on iOS. Photo and video previews expose
system sharing for the resolved local file URL. The app does not upload media or
copy media files into Git.

Chat wallpaper rendering is also lazy. The viewer downscales
`current_wallpaper.jpg` or `current_wallpaper_dark.jpg` from the archive root
before using it as the message background. Wallpaper files are not copied into
Git and full local paths are not shown in the normal UI.

The viewer does not scan or preload all media globally. Missing or unavailable
media stays as a placeholder, while unsupported metadata-only rows are kept out
of the Chat Info media grid. The Chat Info media view queries media for the
selected chat and related merged session IDs directly from SQLite, applies
filters for all renderable media, photos, videos, and reliably detected Stories
/ Status, prioritizes rows with local files, and caps each fetch so it does not
become an archive-wide media scan. A richer media library remains future work.

## Not Yet Used

`ContactsV2.sqlite` is extracted and documented as private data. The viewer uses
it only for conservative read-only enrichment when identifiers map
unambiguously; broader contact enrichment remains future work.
