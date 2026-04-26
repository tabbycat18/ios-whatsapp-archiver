# Privacy

ios-whatsapp-archiver is designed for local, read-only inspection of an iPhone WhatsApp archive.

- No cloud upload is required.
- No server is included.
- The SwiftUI viewer opens `ChatStorage.sqlite` read-only and sets `PRAGMA query_only = ON`.
- Extraction and export tools run on local files selected by the user.
- Open only backups and databases you trust and are authorized to inspect.

## Sensitive Files

The following files and directories can contain private messages, contacts, attachments, or account metadata and must never be committed:

- `ChatStorage.sqlite*`
- `ContactsV2.sqlite*`
- `Media/`
- `Message/`
- iPhone backup folders
- extracted WhatsApp archive folders
- generated HTML exports
- `data/`
- `exports/`

The root `.gitignore` blocks the common private-data paths, but it is not a substitute for checking `git status --short --ignored` before every commit.
