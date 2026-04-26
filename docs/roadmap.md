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
- Full-history pagination branch with latest 500 messages initially and older batches loaded on demand.
- Chat title search, compact message UI, conservative system/call labels, and safer group sender fallbacks on the pagination branch.
- Duplicate-title archive entries are classified so real separate conversations stay visible while system-only or tiny no-visible-message fragments are hidden from normal browsing.
- First chat media rendering path with inline photos, tap-to-play video previews, and simple audio playback.

## Next

- Continue auditing WhatsApp private message-type mappings with public fixtures where possible.
- Continue validating ContactsV2-backed phone-JID and `@lid` migration handling for split one-to-one chats without unsafe title-only merging. ContactsV2 improves identity resolution, but it does not solve every split-session or archive-fragment case yet.
- Add a lightweight debug-only way to inspect hidden technical archive fragments if future diagnostics need it.
- Finish large archive transfer experiment results with the
  [packaged archive transfer experiments](transfer-experiments.md).
- Add packaged archive import support.
- Add a per-chat media library.
- Expand media rendering for documents, contact cards, locations, stickers, and link previews where safe.
- Add `ContactsV2.sqlite` enrichment for better names and contact metadata.
- Expand group sender enrichment where ChatStorage push names are unavailable.
- Add polished archive import and persistent bookmark flow.
- Add a non-Xcode distribution path.
- Improve performance for very large archives and media-heavy chats.
- Add synthetic public test fixtures with no private WhatsApp data.

## Non-Technical User Goal

Eventually users should not need Xcode to extract and read their archive. A
future direction could include a packaged macOS helper for extraction and an iOS
app distribution path for the viewer. Current development still requires Xcode.

## Maintainer Notes

- `prototype-media-metadata-discovery` was superseded by `46c73eb Add media metadata discovery` on `main`.
- Do not delete prototype branches as part of normal documentation or milestone work.
- Keep private archives, exports, and generated HTML out of version control.
