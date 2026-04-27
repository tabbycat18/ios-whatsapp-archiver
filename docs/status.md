# Status and Capabilities

[Back to README](../README.md)

This page is the canonical detailed status list for the current extractor and
viewer. The project is pre-release and under active development.

## Current Capabilities

### Extraction and Archive Opening

- Extract WhatsApp shared-container files from a local iPhone backup.
- Support encrypted backups through the optional `iphone-backup-decrypt`
  package.
- Preserve the extracted archive structure, including SQLite sidecars, media
  folders, and `ContactsV2.sqlite` when present.
- Open an extracted archive folder containing `ChatStorage.sqlite`.
- Open `ChatStorage.sqlite` directly for database-only testing.
- Open a bundled, fully synthetic demo archive from the archive home screen.
- Read offline in-app instructions from the archive home screen.
- Remember selected archives locally so they can be reopened without selecting
  the folder again.
- Manage two local saved archive slots: WhatsApp and WhatsApp Business.
- Rename local archive labels without renaming archive folders.
- Remove saved archive records without deleting archive files.
- Relink moved or stale external archive folders.

For zip or packaged archives, unpack the archive first, then select the
extracted folder containing `ChatStorage.sqlite`. Direct zip/package import is
not implemented.

### Chat Browsing

- Browse chats and text messages from `ZWACHATSESSION` and `ZWAMESSAGE`.
- Search loaded chat titles.
- Search loaded in-chat message text, including media captions stored on the
  message row.
- Open large chats incrementally by loading the latest 250 messages first and
  older messages as the user scrolls upward.
- Preserve message order, dates, sender direction, and bounded memory use.
- Use stable keyset pagination by message date and primary key.
- Keep initial auto-scroll to the newest message without jumping back after
  older messages load.
- Keep security-code and system notices from driving normal chat-list recency.
- Detect likely WhatsApp Status/Stories rows only from reliable message or
  session evidence such as `status@broadcast`.
- Keep reliably detected status/story-only sessions in a separate Stories
  section instead of normal direct-chat browsing.

### Contacts and Sender Labels

- Use `ContactsV2.sqlite` when available for conservative contact-name and
  split-session resolution.
- Optionally match phone-based WhatsApp JIDs to iPhone Contacts after the user
  enables Contacts access from the app.
- Keep Contacts matching local, read-only, and in memory for the app session.
- Avoid requesting Contacts permission on first launch or while opening an
  archive.
- Keep the app functional if Contacts permission is denied or restricted.
- Merge duplicate chat sessions only when they share strong identity evidence,
  such as the same `ZCONTACTJID` or the same unambiguous ContactsV2 identity.
- Keep real duplicate-title conversations separate.
- Hide duplicate system-only or no-visible-message archive fragments from
  normal browsing and chat-title search.
- Show friendly group sender names from reliable archive data when available.
- Show safely extracted phone numbers for unsaved group senders only when a
  classic phone-based WhatsApp JID can be reduced to digits safely.
- Treat `@lid` identifiers and unresolved sender tokens as opaque, showing
  `Unknown sender` rather than guessing.

### Media and Attachments

- Discover `ZWAMEDIAITEM` metadata when the table and columns are available.
- Check whether referenced media files appear available under the selected
  archive root.
- Resolve media paths against common archive-root-relative layouts, including
  `Media/` and `Message/Media/`.
- Render available photo attachments inline after downsampling.
- Open available video attachments in a tap-to-play video preview.
- Treat instant video/video-message rows as video when file, MIME, duration, or
  message-type evidence supports it.
- Play available audio and voice attachments with a simple play/pause control.
- Share available audio from the chat row.
- Show PDF and common document attachments as document rows with safe title,
  type, size, local preview, and sharing when the file resolves.
- Show captions under photo, video, audio, and document attachments in the same
  message bubble.
- Share photos and videos from local preview sheets.
- Keep missing, unreadable, or unsupported media as placeholders.
- Show conservative system, call, and deleted-message placeholders without
  exposing raw sender IDs.
- Open a lightweight Chat Info screen with per-chat filters for all previewable
  media, photos, videos, and documents.
- Prioritize available local media in Chat Info while keeping missing or
  unresolved items as placeholders.
- Support grouped sharing/export for selected available local files in Chat
  Info.
- Keep voice-message audio in chat rows instead of the media grid.

Media rendering is lazy. The app does not scan or preload all archive media,
does not upload media, and does not copy media files into Git.

### Appearance and Demo Fixture

- Show local profile pictures lazily in the chat list when profile/avatar cache
  files are present in the selected archive.
- Show initials immediately while avatar lookup runs in the background.
- Support a local chat wallpaper selector: Archive Default, Classic, Soft
  Pattern, Demo, and Plain.
- Use extracted `current_wallpaper.jpg` or `current_wallpaper_dark.jpg` files
  from the archive root when present and Archive Default is selected.
- Generate the built-in wallpaper styles inside the app without modifying
  archive files.
- Bundle a fully synthetic demo archive under `test-fixtures/demo-archive/`.
- Keep the demo separate from the WhatsApp and WhatsApp Business archive slots.

The synthetic demo archive contains no real WhatsApp data. Screenshots for demos
or documentation should come from the synthetic archive, not private chats.

## Completed Milestones

- Clean public repo split from the original Android viewer prototype.
- Local iPhone backup extraction tool.
- Native SwiftUI archive viewer.
- Real `ChatStorage.sqlite` browsing.
- Chat list loading from `ZWACHATSESSION`.
- Per-chat message loading from `ZWAMESSAGE`.
- Message dates, ordering, and sender direction validation.
- Media metadata and safe path discovery.
- Full-history pagination with latest messages first and older batches loaded
  on demand.
- Chat title search, compact message UI, conservative system/call labels, and
  safer group sender fallbacks.
- Duplicate-title archive entry classification.
- Inline photos, tap-to-play video previews, simple audio playback, document
  rows, captions, and local share actions.
- Chat wallpaper rendering from archive-root wallpaper files and generated app
  styles.
- Conservative WhatsApp Status/Stories detection and separation.
- Photo preview zoom on iOS.
- First lightweight Chat Info media view.
- Instant video/video-message rows classified as playable video when reliable
  video evidence is present.
- Security-code/system notices excluded from normal chat-list recency.
- Local saved archive library with bookmark reopening, multi-archive switching,
  relinking, and remove-record support.
- Two-slot archive selection for WhatsApp and WhatsApp Business.
- Bundled fully synthetic demo archive entry on the archive home screen.
- Offline in-app Help / Instructions for backup, extraction, transfer, privacy,
  demo usage, and installation status.
- Optional iPhone Contacts matching for phone-based WhatsApp participants with
  explicit permission flow and denied-permission fallback.

## Current Limitations

- Installation is currently developer/Xcode-oriented. The source is on GitHub,
  but the repository does not provide a universal one-tap iPhone install path.
- TestFlight, App Store, EU alternative distribution, and Web Distribution are
  possible future distribution options only if requirements are met.
- Direct zip/package import is not implemented.
- App document sharing through Finder is not configured yet; use the app's Add
  Archive flow with a local or iCloud Drive archive folder.
- The Chat Info media view is intentionally lightweight and capped per filtered
  query. It is not a complete archive-wide media browser.
- Link previews, locations, contact cards, and stickers remain placeholders or
  conservative classifications unless reliable metadata is available.
- ContactsV2 enrichment is intentionally conservative and may not resolve every
  historical contact edge case.
- `@lid` identifiers remain opaque unless a safe mapping exists.
- Duplicate-title sessions can still represent either real separate chats or
  archive fragments that need conservative classification.
- Media support is best effort and lazy; missing, unsupported, or unreadable
  files remain placeholders.
- Very large raw archive transfers can be slow and may require substantial free
  space.
- WhatsApp private schema details are not fully mapped.

## Known Issues and Caveats

- Selecting the archive folder is preferred over selecting
  `ChatStorage.sqlite` directly because media availability checks and wallpaper
  lookup use the archive root.
- External archive folders may need relinking if moved or if iOS marks a saved
  bookmark stale.
- Large iCloud Drive folders may appear locally before upload or sync has
  finished. Wait for upload/sync completion and ensure the folder is downloaded
  locally on iPhone before opening it.
- AirDrop can work for large archives, but the iPhone may spend additional time
  saving the received data after progress appears mostly complete.
- Packaging a large archive may reduce many-small-file transfer overhead, but
  it does not necessarily reduce size and requires extra free space for both the
  package and unpacked archive.
- Third-party transfer services change the privacy model and are entirely
  user-managed.

## More Detail

- [User guide](user-guide.md)
- [iPhone backup extraction](iphone-backup-extraction.md)
- [Archive format](archive-format.md)
- [Architecture](architecture.md)
- [Roadmap](roadmap.md)
- [Development](development.md)
- [Large archive transfer experiments](transfer-experiments.md)
