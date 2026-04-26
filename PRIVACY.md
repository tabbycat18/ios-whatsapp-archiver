# Privacy

ios-whatsapp-archiver is designed for local, read-only inspection of an iPhone WhatsApp archive.

- No cloud upload is required.
- No server is included.
- The SwiftUI viewer opens `ChatStorage.sqlite` read-only and sets `PRAGMA query_only = ON`.
- iPhone Contacts access is optional. If enabled by the user, Contacts are read
  locally and used only to match saved display names to phone-based WhatsApp
  identifiers. Contacts are not uploaded and the full contact list is not
  persisted.
- The app continues to work when Contacts permission is denied or restricted.
- Extraction and export tools run on local files selected by the user.
- Data stays local unless you manually transfer it somewhere else.
- iCloud Drive or another Files provider can be used as an optional user-managed transfer method, but that is outside this project's local privacy model.
- Third-party transfer services are outside this project. Uploading an archive
  to such a service may expose sensitive chat, contact, and media data depending
  on the service, settings, retention period, and link access controls.
- Local-only transfer remains the privacy-preserving default.
- Open only backups and databases you trust and are authorized to inspect.

## Sensitive Files

The following files and directories can contain private messages, contacts, attachments, or account metadata and must never be committed:

- `ChatStorage.sqlite*`
- `ContactsV2.sqlite*`
- device Contacts, when optional matching is enabled
- `Media/`
- `Message/`
- iPhone backup folders
- extracted WhatsApp archive folders
- generated HTML exports
- `data/`
- `exports/`

The root `.gitignore` blocks the common private-data paths, but it is not a substitute for checking `git status --short --ignored` before every commit.
