# iPhone Backup Extraction

The extraction tool targets WhatsApp files inside an iPhone backup.

```bash
python3 tools/extract_ios_whatsapp_backup.py /path/to/iPhone/Backup exports/whatsapp-extracted
```

For encrypted backups, install the optional dependency and omit `--password` to be prompted locally:

```bash
python3 -m pip install iphone-backup-decrypt
python3 tools/extract_ios_whatsapp_backup.py /path/to/iPhone/Backup exports/whatsapp-extracted
```

Extracted output may contain `ChatStorage.sqlite`, `ContactsV2.sqlite`, `Media/`, `Message/`, and other private files. Keep it under an ignored folder such as `exports/`.
