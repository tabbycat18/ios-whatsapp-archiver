# Contributing

Contributions should keep the project focused on local, read-only iPhone WhatsApp archive inspection.

Before opening a change:

1. Do not include private WhatsApp data, generated HTML, backups, databases, or media.
2. Run `git status --short --ignored`.
3. Confirm no ignored private-data paths are staged.
4. Prefer synthetic fixtures and schema-only examples.

The SwiftUI viewer lives under `apps/ios-archive-viewer/`. Local extraction utilities live under `tools/`.
