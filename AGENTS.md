# AGENTS.md

Guidance for Codex and other AI/code agents working in this repository.

When starting work, first read `AGENTS.md` and the relevant docs. Then inspect
git status before editing.

## Project Summary

iOS WhatsApp Archiver is a local, read-only iPhone WhatsApp backup extractor
and viewer. The SwiftUI app lives under `apps/ios-archive-viewer`, Python tools
live under `tools`, and the public synthetic demo fixture lives under
`test-fixtures/demo-archive`.

## Critical Privacy Rules

- Never commit private WhatsApp data.
- Never stage `data/`, `exports/`, `ChatStorage.sqlite`, `ContactsV2.sqlite`,
  `Media/`, or `Message/`, except for the synthetic demo fixture under
  `test-fixtures/demo-archive`.
- Never print private message contents or full private media paths in logs,
  summaries, test output, screenshots, or docs.
- Keep extracted archives local and ignored.
- Do not weaken `.gitignore` protections for private archives, generated
  exports, SQLite databases, media folders, or Xcode user state.

## Git Workflow

- Do not push unless explicitly asked.
- Prefer local commits only for coherent units.
- Leave experimental diffs uncommitted if uncertain.
- Use explicit `git add` paths, not `git add .`.
- Never commit local signing noise such as `DEVELOPMENT_TEAM`.
- Report final git status.

## Codex Workflows

- For ambiguous technical or product decisions, use the Codex-specific
  [Decision Council](docs/ai-council.md) workflow.

## Validation Expectations

- Run `git diff --check`.
- Run `plutil -lint apps/ios-archive-viewer/WhatsAppArchiveViewer.xcodeproj/project.pbxproj`.
- Run Swift typecheck with the module cache under `/tmp`.
- Run `xcodebuild` if full Xcode is available and the task touches app code.
- Run a private-data scan before committing.
- Run SQLite integrity checks for generated demo fixtures when the fixture
  changes.

## Key Docs To Read

- [README.md](README.md)
- [docs/architecture.md](docs/architecture.md)
- [docs/archive-format.md](docs/archive-format.md)
- [docs/iphone-backup-extraction.md](docs/iphone-backup-extraction.md)
- [docs/distribution.md](docs/distribution.md)
- [docs/roadmap.md](docs/roadmap.md)
- [PRIVACY.md](PRIVACY.md)
- [SECURITY.md](SECURITY.md)

## App Architecture Notes

- SQLite access must remain read-only.
- `ChatStorage.sqlite` and `ContactsV2.sqlite` are external/user archives, not
  app-owned data.
- Media loading must be lazy; do not eagerly scan or load full media archives.
- Status/story detection must remain conservative.
- Do not regress chat-list filtering of system/archive fragments.

## Demo Fixture Rules

- Demo data must be fully synthetic.
- The generator should be deterministic.
- Keep the fixture small enough for GitHub.
- Synthetic demo archive files are allowed only under
  `test-fixtures/demo-archive`.
