# Release Checklist

[Back to distribution notes](distribution.md)

Use this checklist before preparing a TestFlight, App Store, ad hoc, or other
signed release build.

## Repository Safety

- Verify `git status --short --ignored`.
- Verify no private WhatsApp data is staged or committed.
- Verify `data/`, `exports/`, local backups, and generated exports remain
  ignored.
- Verify the demo fixture is fully synthetic and lives only under
  `test-fixtures/demo-archive/`.
- Verify signing and team settings such as `DEVELOPMENT_TEAM` are not committed.

## App Metadata

- Bump `MARKETING_VERSION` when preparing a user-visible release.
- Bump `CURRENT_PROJECT_VERSION` for the build number.
- Verify the app icon and launch appearance.
- Verify the bundle identifier is correct for the intended signing team and
  distribution channel.

## Validation

- Run `git diff --check`.
- Run `plutil -lint apps/ios-archive-viewer/WhatsAppArchiveViewer.xcodeproj/project.pbxproj`.
- Run Swift typecheck or `xcodebuild` when full Xcode is available.
- Run a private-data scan for databases, media folders, generated HTML, local
  virtual environments, Xcode user state, and unexpected large files.
- Run SQLite integrity checks for generated demo fixtures when the fixture
  changes.
- Smoke test on a real device.

## Distribution

- Archive in Xcode.
- Upload to TestFlight when ready for tester validation.
- Complete beta review for external TestFlight testing when required.
- Update GitHub release notes with user-facing changes and known limits.
- Tag the release after the release artifact and notes are final.
