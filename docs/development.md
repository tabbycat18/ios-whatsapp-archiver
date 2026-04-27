# Development

[Back to README](../README.md)

This page collects developer setup notes, fixture commands, and the manual
testing checklist. Product capability details live in
[Status and capabilities](status.md).

## Xcode Build Notes

Open the project from the repository root:

```bash
open apps/ios-archive-viewer/WhatsAppArchiveViewer.xcodeproj
```

Build and run with full Xcode on an iOS simulator or device. Command Line Tools
alone are not enough for simulator builds.

The current install path is developer/Xcode-oriented. The repository does not
currently provide TestFlight, App Store, or one-tap iPhone installation.

Do not commit local signing or user state changes from Xcode. In particular,
review `project.pbxproj`, `xcuserdata/`, and workspace user files before any
commit.

## Development Data

For simulator development, a local development copy of `ChatStorage.sqlite` can
be placed in the app container's Documents folder as:

```text
Documents/ChatStorage.sqlite
```

If sidecar files are present, copy them next to it too:

```text
Documents/ChatStorage.sqlite-wal
Documents/ChatStorage.sqlite-shm
Documents/ChatStorage.sqlite-journal
```

The app starts at an archive selection screen with two account slots: WhatsApp
and WhatsApp Business. Each slot can select either an extracted archive folder
containing `ChatStorage.sqlite` or the database file directly. Picking the
containing folder is preferred because the selected folder becomes the archive
root for media availability checks.

Saved archive labels are local app metadata and can be renamed without renaming
or moving archive folders. The app stores security-scoped bookmark metadata when
appropriate and opens the selected database in place. It does not copy the
archive or media binaries into the app sandbox. If an external folder is moved
or the bookmark becomes stale, relink the saved archive from its slot.

Avoid repeatedly transferring a full real archive during development. Start with
the database and sidecars, then add a small media subset only when media
behavior is being tested.

## Synthetic Demo Fixture

The app target bundles the public fixture at:

```text
test-fixtures/demo-archive/
```

Tap `Try Demo Archive` on the archive home screen to open it. The demo is
clearly labeled `Demo Archive`, does not occupy the WhatsApp or WhatsApp
Business slots, and does not create a saved archive record.

Developers can regenerate the fixture from the repository root:

```bash
python3 tools/generate_demo_archive.py
```

Developers can also test manual archive picking by selecting
`test-fixtures/demo-archive/` through the normal Add flow. Selecting the folder
is preferred over selecting `ChatStorage.sqlite` directly because sidecar files,
media, and wallpaper lookup resolve relative to the archive root.

The fixture contains no real WhatsApp data. Screenshots for demos or docs should
come from the synthetic demo archive, not private chats.

## Manual Testing Checklist

- Confirm the archive home Help entry is visible and the Instructions screen
  opens offline.
- On the archive home screen, confirm `Try Demo Archive` opens synthetic chats
  and does not fill either real archive slot.
- Test with a large chat and confirm the latest 250 messages appear first.
- Search for a known chat title, then clear search and confirm all chats return.
- Search for duplicate-title contacts and confirm real separate conversations
  remain visible while system-only fragments do not drive normal results.
- Scroll upward and confirm older rows load automatically near the top.
- Confirm ordering remains oldest-to-newest.
- Confirm sender direction and dates remain correct.
- Confirm media placeholders still appear.
- Confirm available photos render inline without large layout jumps.
- Confirm photo preview pinch-to-zoom works.
- Confirm photo and video preview sharing opens the system share sheet.
- Confirm available videos open in the video preview only after tapping.
- Confirm instant video/video-message rows are not shown as contact cards or
  Location placeholders and can be opened from the chat row.
- Confirm available audio or voice rows can play and pause.
- Confirm available audio or voice rows can be shared from the chat row.
- Confirm PDF/document rows show safe titles, type, size, open in the system
  preview, and can be shared.
- Confirm photo, video, audio, and document rows with captions show the caption
  below the media in the same bubble.
- Confirm message search finds media caption text.
- Confirm a saved archive is listed after force quit and can be opened without
  reselecting the folder.
- Confirm the WhatsApp and WhatsApp Business slots can be opened and switched
  from the archive selection screen.
- Confirm no more than one saved archive can be added per slot.
- Confirm local archive labels can be renamed without changing archive folder
  names.
- Confirm removing a saved archive record does not delete the archive files.
- Confirm the chat wallpaper appears behind messages when
  `current_wallpaper.jpg` is present in the selected archive folder.
- Confirm missing or unreadable media remains a clean placeholder.
- Confirm missing or unreadable documents show `Document unavailable`.
- Confirm call and system rows use neutral labels instead of generic
  unsupported text where possible.
- Confirm the viewer does not auto-scroll back to newest after loading older
  messages.
- Confirm raw/debug identifiers are not shown in the normal message UI.
- Confirm unresolved group senders show `Unknown sender` instead of raw opaque
  tokens.
- Confirm the app does not request Contacts permission on first launch or when
  opening an archive.
- From an open chat list, use More -> Use iPhone Contacts, grant permission, and
  confirm matching phone-based chat titles or group sender labels improve while
  the app stays responsive.
- Deny Contacts permission on another test install if possible, then confirm the
  app still opens archives and the menu explains that Contacts can be enabled in
  iOS Settings.
- Confirm chat list dates for duplicate-title conversations come from
  user-visible text, media, or call rows rather than security/system-only
  fragments.
- Confirm security-code/system notices do not push a normal chat to the top of
  the chat list.
- Confirm media rendering does not break automatic older-message loading.
- Confirm detected status/story-only entries appear under Stories rather than as
  normal chats.
- Confirm Chat Info -> Media shows available All, Photos, Videos, and Docs items
  before missing placeholders when the archive contains local files, and does
  not show Stories rows.
- Confirm Chat Info -> Media can tap-select or drag-select multiple available
  items, select all shown available items, and share/export them together.
- Avoid printing private message contents or full private filesystem paths
  during debugging.

## Privacy Checks Before Committing

- Keep extracted archives under ignored folders such as `data/` or `exports/`.
- Do not commit `ChatStorage.sqlite`, `ContactsV2.sqlite`, `Media/`, `Message/`,
  generated HTML exports, screenshots from private chats, or copied backups.
- Keep screenshot fixtures synthetic and derived from
  `test-fixtures/demo-archive/`.
- Run `git status --short --ignored` before every commit.
