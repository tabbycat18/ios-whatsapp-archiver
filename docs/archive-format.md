# Archive Format

The validated viewer path currently focuses on the iOS WhatsApp `ChatStorage.sqlite` database.

## Current Tables

- `ZWACHATSESSION`: chat/session metadata.
- `ZWAMESSAGE`: message rows for a chat.

## Current Fields

The viewer uses fields needed for chat title, message count, latest message date, sender direction, sender label, message text, and message date.

`ContactsV2.sqlite`, `Media/`, and `Message/` are not used in the validated Milestone 1 viewer state.
