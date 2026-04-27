# Roadmap

## Completed

- Clean public repo split from the original Android viewer prototype.
- Local iPhone backup extraction tool.
- Native SwiftUI iPhone/iPad archive viewer.
- Real `ChatStorage.sqlite` browsing.
- Chat list loading from `ZWACHATSESSION`.
- Per-chat message loading from `ZWAMESSAGE`.
- Message dates, ordering, and sender direction validation.
- Media metadata and path discovery merged on `main`.
- Full-history pagination with latest 500 messages initially and older batches
  loaded on demand.
- Chat title search, compact message UI, conservative system/call labels, and
  safer group sender fallbacks.
- Duplicate-title archive entries are classified so real separate conversations stay visible while system-only or no-visible-message fragments are hidden from normal browsing.
- First chat media rendering path with inline photos, tap-to-play video previews, and simple audio playback.
- Chat wallpaper rendering from generic archive-root `current_wallpaper.jpg` and `current_wallpaper_dark.jpg` files, plus a local Archive Default/Classic/Soft Pattern/Demo/Plain selector.
- Conservative WhatsApp Status/Stories detection from `status@broadcast` schema/session evidence, with status/story-only fragments separated from normal chats.
- Photo preview zoom and photo/video local share-sheet support.
- PDF and common document attachment rows with system preview/share support.
- First lightweight Chat Info media view with per-chat photo/video/document filters and available local media prioritized ahead of missing placeholders.
- Instant video/video-message rows with video evidence render as playable video rather than contact-card or location placeholders.
- Security-code/system notices are excluded from normal chat-list latest-date sorting.
- Local saved archive library with security-scoped bookmark reopening, multi-archive switching, relinking, and remove-record support.
- Two-slot archive selection for WhatsApp and WhatsApp Business, with local labels and relinking/removal that does not delete archive files.
- Captions on photo, video, audio, and document messages rendered under the attachment in the same bubble.
- Bundled fully synthetic demo archive entry on the archive home screen.
- Polished archive home actions with explicit Open, Add, Relink, and More controls.
- Offline in-app Help / Instructions for backup, extraction, transfer, privacy, demo usage, and installation status.
- Optional iPhone Contacts matching for phone-based WhatsApp participants, with
  explicit permission flow, in-memory local matching, and denied-permission
  fallback.

## Next

- Continue auditing WhatsApp private message-type mappings with public fixtures where possible.
- Expand the Stories area into a richer media browser if more archive shapes are validated.
- Continue validating ContactsV2-backed phone-JID and `@lid` migration handling for split one-to-one chats without unsafe title-only merging. ContactsV2 improves identity resolution, but it does not solve every split-session or archive-fragment case yet.
- Add a lightweight debug-only way to inspect hidden technical archive fragments if future diagnostics need it.
- Finish large archive transfer experiment results with the
  [packaged archive transfer experiments](transfer-experiments.md).
- Add packaged archive import support.
- Replace the lightweight Chat Info media grid with a fuller per-chat media library.
- Expand media rendering for contact cards, locations, stickers, and link previews where safe.
- Continue expanding safe contact enrichment where `ContactsV2.sqlite`, iPhone
  Contacts, or future public fixtures expose reliable phone mappings.
- Expand group sender enrichment where ChatStorage push names are unavailable
  without guessing from `@lid` or opaque identifiers.
- Add a non-Xcode distribution path.
- Continue improving first-run guidance and release packaging for non-developer users.
- Improve performance for very large archives and media-heavy chats.
- Add release packaging around demo and archive-opening workflows for non-Xcode users.

## Non-Technical User Goal

Eventually users should not need Xcode to extract and read their archive. A
future direction could include a packaged macOS helper for extraction and an iOS
app distribution path for the viewer. Current development still requires Xcode.

## Maintainer Notes

- `prototype-media-metadata-discovery` was superseded by `46c73eb Add media metadata discovery` on `main`.
- Do not delete prototype branches as part of normal documentation or milestone work.
- Keep private archives, exports, and generated HTML out of version control.
