# Synthetic Demo WhatsApp Archive

This is a fully synthetic demo archive for iOS WhatsApp Archiver.

It contains no real WhatsApp data, no real phone numbers, no real addresses, no
real tickets, no real receipts, and no private messages. The `+1 555 0100`
through `+1 555 0109` identifiers are reserved demo/test-style numbers used for
fictional contacts only.

## Regenerate

```sh
python3 tools/generate_demo_archive.py
```

The generator deletes and recreates only `test-fixtures/demo-archive/` and
refuses to operate outside that path.

## Load In The App

Run the iOS viewer, choose Add Archive, and select this directory:

```text
test-fixtures/demo-archive/
```

Selecting the folder is preferred over selecting `ChatStorage.sqlite` directly
because media availability checks and `current_wallpaper.jpg` resolution use the
archive root.

## Feature Coverage

- chat list
- one-to-one chats
- group chats
- latest-message ordering
- pagination-ready message dates and IDs
- chat search
- in-chat search
- group sender labels
- system messages
- voice call labels
- photos, videos, audio, voice memos, stickers, and contact cards
- PDFs/documents
- media captions
- Stories / Status rows via `status@broadcast`
- wallpaper via `current_wallpaper.jpg`
- Chat Info / Media filters
- intentionally missing media behavior

## Test Search Terms

- lake
- ticket
- PDF
- snacks

## Notes

Image placeholders are tiny generated PNG bitstreams stored with the requested
fixture filenames, including `.jpg` names, so the app can test image-path and
media-kind behavior without copyrighted or private images. Video placeholders are
small deterministic MP4-like files. They exercise existence, type inference, and
unavailable-thumbnail behavior; they are not intended to be real playable clips.

## Validation Summary

- Conversations: 10
- One-to-one chats: 8
- Group chats: 2
- Status/story sessions: 1
- Messages: 225
- Lake Weekend messages: 72
- Fixture size: 217866 bytes
