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

## Next

- Merge the Milestone 2.5 pagination PR.
- Document and validate large archive transfer workflows with the
  [packaged archive transfer experiments](transfer-experiments.md).
- Experiment with packaged archive import.
- Add first image rendering path.
- Add video rendering.
- Add audio and voice-note rendering.
- Add `ContactsV2.sqlite` enrichment for better names and contact metadata.
- Add polished archive import and persistent bookmark flow.
- Improve performance for very large archives and media-heavy chats.
- Add synthetic public test fixtures with no private WhatsApp data.

## Maintainer Notes

- `prototype-media-metadata-discovery` was superseded by `46c73eb Add media metadata discovery` on `main`.
- Do not delete prototype branches as part of normal documentation or milestone work.
- Keep private archives, exports, and generated HTML out of version control.
