#!/usr/bin/env python3
"""Generate the fully synthetic demo archive fixture.

All generated data is fictional and intended only for app testing. The script
does not read private WhatsApp data, does not inspect user data directories, and
refuses to write outside test-fixtures/demo-archive.
"""

from __future__ import annotations

import json
import math
import os
import shutil
import sqlite3
import struct
import wave
import zlib
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path


GENERATOR_VERSION = "1.0"
REPO_ROOT = Path(__file__).resolve().parents[1]
FIXTURE_ROOT = REPO_ROOT / "test-fixtures" / "demo-archive"
APPLE_EPOCH = datetime(2001, 1, 1, tzinfo=timezone.utc)
MAX_FIXTURE_BYTES = 20 * 1024 * 1024

SYNTHETIC_NOTICE = (
    "Fully synthetic demo fixture. Contains no real WhatsApp data, no real "
    "private messages, no real tickets, no real receipts, and no real addresses."
)


FONT = {
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    "G": ["01111", "10000", "10000", "10111", "10001", "10001", "01111"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
    "J": ["00111", "00010", "00010", "00010", "10010", "10010", "01100"],
    "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
    "W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
    "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
    "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5": ["11111", "10000", "10000", "11110", "00001", "00001", "11110"],
    "6": ["01110", "10000", "10000", "11110", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00001", "01110"],
    " ": ["000", "000", "000", "000", "000", "000", "000"],
    "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
    "/": ["00001", "00010", "00010", "00100", "01000", "01000", "10000"],
    ".": ["000", "000", "000", "000", "000", "011", "011"],
    ":": ["000", "011", "011", "000", "011", "011", "000"],
}


CHARACTERS = {
    "alex": {
        "name": "Alex Rivera",
        "nickname": "Alex",
        "initials": "AR",
        "relationship": "main user",
        "personality": "careful, friendly, overplans slightly",
        "role": "owner of the demo archive",
        "phone": "+1 555 0100",
        "jid": "15550100@s.whatsapp.net",
    },
    "maya": {
        "name": "Maya Chen",
        "nickname": "Maya",
        "initials": "MC",
        "relationship": "best friend",
        "personality": "funny, direct, sends voice notes",
        "role": "helps Alex plan the lake weekend and teases Alex about overplanning",
        "phone": "+1 555 0101",
        "jid": "15550101@s.whatsapp.net",
    },
    "samir": {
        "name": "Samir Patel",
        "nickname": "Sam",
        "initials": "SP",
        "relationship": "organizer friend",
        "personality": "structured, practical, spreadsheet-minded",
        "role": "sends PDF plan, corrects details, handles tickets and packing list",
        "phone": "+1 555 0102",
        "jid": "15550102@s.whatsapp.net",
    },
    "nina": {
        "name": "Nina Rossi",
        "nickname": "Nina",
        "initials": "NR",
        "relationship": "friend who feels left out",
        "personality": "warm but sensitive",
        "role": "harmless drama because she thought she was not invited",
        "phone": "+1 555 0103",
        "jid": "15550103@s.whatsapp.net",
    },
    "theo": {
        "name": "Theo Martin",
        "nickname": "Theo",
        "initials": "TM",
        "relationship": "coworker",
        "personality": "concise, logistical",
        "role": "coordinates coworking meetup and transport",
        "phone": "+1 555 0104",
        "jid": "15550104@s.whatsapp.net",
    },
    "elena": {
        "name": "Elena Rivera",
        "nickname": "Mom",
        "initials": "ER",
        "relationship": "family member",
        "personality": "warm, caring, sends photos/audio",
        "role": "checks on Alex and sends a family photo",
        "phone": "+1 555 0105",
        "jid": "15550105@s.whatsapp.net",
    },
    "jules": {
        "name": "Jules Meyer",
        "nickname": "Jules",
        "initials": "JM",
        "relationship": "ticket seller/buyer",
        "personality": "practical but slow to reply",
        "role": "ticket exchange, unresolved",
        "phone": "+1 555 0106",
        "jid": "15550106@s.whatsapp.net",
    },
    "priya": {
        "name": "Priya Shah",
        "nickname": "Pri",
        "initials": "PS",
        "relationship": "quiet contact / old friend",
        "personality": "brief, calm",
        "role": "small old chat for testing short histories",
        "phone": "+1 555 0107",
        "jid": "15550107@s.whatsapp.net",
    },
    "studio": {
        "name": "Green Corner Studio",
        "nickname": "Studio",
        "initials": "GC",
        "relationship": "fictional business/service contact",
        "personality": "polite automated-ish tone",
        "role": "picnic basket / print order / appointment receipt",
        "phone": "+1 555 0108",
        "jid": "15550108@s.whatsapp.net",
    },
    "leo": {
        "name": "Leo Grant",
        "nickname": "Leo",
        "initials": "LG",
        "relationship": "friend of the group",
        "personality": "jokes, distractible",
        "role": "forgets snacks, causes mild ticket/transport confusion",
        "phone": "+1 555 0109",
        "jid": "15550109@s.whatsapp.net",
    },
}


MEDIA_LIBRARY = {
    "photo_picnic_blanket.jpg": {"kind": "photo", "path": "Media/Photos/photo_picnic_blanket.jpg", "caption": "testing the picnic blanket situation", "label": "DEMO PICNIC BLANKET", "available": True},
    "photo_meeting_point.jpg": {"kind": "photo", "path": "Media/Photos/photo_meeting_point.jpg", "caption": "Updated meeting point screenshot", "label": "DEMO MEETING MAP", "available": True},
    "photo_old_birthday.jpg": {"kind": "photo", "path": "Media/Photos/photo_old_birthday.jpg", "caption": "Found this old birthday photo.", "label": "BIRTHDAY CARD", "available": True},
    "photo_lake_view.jpg": {"kind": "photo", "path": "Media/Photos/photo_lake_view.jpg", "caption": "not the actual lake but manifesting this energy", "label": "DEMO LAKE", "available": True},
    "photo_snack_table.jpg": {"kind": "photo", "path": "Media/Photos/photo_snack_table.jpg", "caption": "snack table prototype", "label": "SNACK TABLE", "available": True},
    "photo_ticket_preview_fake.jpg": {"kind": "photo", "path": "Media/Photos/photo_ticket_preview_fake.jpg", "caption": "fake preview, not a real ticket", "label": "DEMO ONLY TICKET", "available": True},
    "photo_group_selfie_placeholder.jpg": {"kind": "photo", "path": "Media/Photos/photo_group_selfie_placeholder.jpg", "caption": "group photo placeholder", "label": "ABSTRACT AVATARS", "available": True},
    "photo_missing_boat_sign.jpg": {"kind": "photo", "path": "Media/Photos/photo_missing_boat_sign.jpg", "caption": "boat sign, if it uploads", "label": "MISSING BOAT SIGN", "available": False, "expected_missing_label": "Media missing"},
    "photo_green_corner_basket.jpg": {"kind": "photo", "path": "Media/Photos/photo_green_corner_basket.jpg", "caption": "basket placeholder", "label": "DEMO ORDER", "available": True},
    "sticker_tiny_drama.png": {"kind": "sticker", "path": "Media/Stickers/sticker_tiny_drama.png", "caption": "tiny drama sticker", "label": "TINY DRAMA", "available": True},
    "sticker_snack_vote.png": {"kind": "sticker", "path": "Media/Stickers/sticker_snack_vote.png", "caption": "snack vote sticker", "label": "SNACK VOTE", "available": True},
    "video_lake_pan.mp4": {"kind": "video", "path": "Media/Videos/video_lake_pan.mp4", "caption": "dramatic 3 second lake pan", "label": "DEMO LAKE PAN", "duration": 3, "available": True},
    "video_snack_unboxing.mp4": {"kind": "video", "path": "Media/Videos/video_snack_unboxing.mp4", "caption": "unboxing the emergency snacks", "label": "DEMO SNACK VIDEO", "duration": 5, "available": True},
    "video_instant_note.mp4": {"kind": "video_message", "path": "Media/Videos/video_instant_note.mp4", "caption": "instant video note placeholder", "label": "VIDEO NOTE", "duration": 4, "available": True},
    "audio_maya_snack_math.wav": {"kind": "voice", "path": "Media/Audio/audio_maya_snack_math.wav", "caption": "Maya explains snack math for 18 seconds", "label": "MAYA SNACK MATH", "duration": 18, "available": True},
    "audio_elena_birthday_note.wav": {"kind": "voice", "path": "Media/Audio/audio_elena_birthday_note.wav", "caption": "Elena says happy early birthday and reminds Alex to eat properly", "label": "ELENA BIRTHDAY NOTE", "duration": 15, "available": True},
    "audio_group_leo_explains.wav": {"kind": "voice", "path": "Media/Audio/audio_group_leo_explains.wav", "caption": "Leo explains the ticket confusion", "label": "LEO TICKET NOTE", "duration": 22, "available": True},
    "audio_office_vote.wav": {"kind": "audio", "path": "Media/Audio/audio_office_vote.wav", "caption": "Theo votes for salty snacks", "label": "OFFICE VOTE AUDIO", "duration": 9, "available": True},
    "lake_weekend_plan.pdf": {"kind": "document", "path": "Media/Documents/lake_weekend_plan.pdf", "caption": "Lake weekend PDF plan", "label": "LAKE WEEKEND PLAN", "available": True},
    "green_corner_receipt.pdf": {"kind": "document", "path": "Media/Documents/green_corner_receipt.pdf", "caption": "Synthetic receipt PDF", "label": "GREEN CORNER RECEIPT", "available": True},
    "office_snack_rotation.pdf": {"kind": "document", "path": "Media/Documents/office_snack_rotation.pdf", "caption": "Office snack rotation PDF", "label": "OFFICE SNACK ROTATION", "available": True},
    "ticket_notes_demo.pdf": {"kind": "document", "path": "Media/Documents/ticket_notes_demo.pdf", "caption": "demo ticket note", "label": "DEMO TICKET NOTE", "available": True},
    "contact_jules.vcf": {"kind": "contact", "path": None, "caption": "Possible spare ticket contact", "label": "JULES CONTACT", "available": False, "vcard_name": "Jules Meyer", "vcard_string": "BEGIN:VCARD\nVERSION:3.0\nFN:Jules Meyer\nTEL:+15550106\nNOTE:Synthetic demo contact card, not real contact data\nEND:VCARD"},
    "status_alex_lake_countdown.jpg": {"kind": "status_photo", "path": "Stories/status_alex_lake_countdown.jpg", "caption": "lake countdown", "label": "LAKE COUNTDOWN", "available": True},
    "status_maya_snacks.jpg": {"kind": "status_photo", "path": "Stories/status_maya_snacks.jpg", "caption": "snacks secured", "label": "SNACKS SECURED", "available": True},
    "status_samir_pdf_done.jpg": {"kind": "status_photo", "path": "Stories/status_samir_pdf_done.jpg", "caption": "PDF finally sent", "label": "PDF DONE", "available": True},
    "wallpaper_demo_green_gradient.jpg": {"kind": "wallpaper", "path": "Wallpapers/wallpaper_demo_green_gradient.jpg", "caption": "synthetic wallpaper", "label": "DEMO WALLPAPER", "available": True},
}

@dataclass
class Message:
    stable_id: str
    chat_key: str
    timestamp: datetime
    sender: str
    text: str = ""
    message_type: int = 0
    media_key: str | None = None
    media_available: bool = True
    expected_missing_label: str | None = None
    latitude: float | None = None
    longitude: float | None = None
    duration: float | None = None
    group_event_type: int | None = None


@dataclass
class Chat:
    key: str
    title: str
    chat_type: str
    jid: str
    participant_keys: list[str]
    messages: list[Message] = field(default_factory=list)


def apple_time(value: datetime) -> float:
    return (value - APPLE_EPOCH).total_seconds()


def dt(day: int, hour: int, minute: int) -> datetime:
    return datetime(2026, 4, day, hour, minute, tzinfo=timezone.utc)


def old_dt() -> datetime:
    return datetime(2026, 3, 8, 15, 45, tzinfo=timezone.utc)


def assert_safe_fixture_root() -> None:
    target = FIXTURE_ROOT.resolve()
    expected = (REPO_ROOT / "test-fixtures" / "demo-archive").resolve()
    allowed_parent = (REPO_ROOT / "test-fixtures").resolve()
    if target != expected or target.parent != allowed_parent:
        raise RuntimeError(f"Refusing to write outside synthetic fixture root: {target}")
    if "demo-archive" not in target.parts:
        raise RuntimeError(f"Refusing suspicious fixture path: {target}")


def recreate_fixture_root() -> None:
    assert_safe_fixture_root()
    if FIXTURE_ROOT.exists():
        shutil.rmtree(FIXTURE_ROOT)
    for subdir in ["Media", "Message/Media", "Wallpapers", "Stories", "Status"]:
        (FIXTURE_ROOT / subdir).mkdir(parents=True, exist_ok=True)


def set_pixel(pixels: bytearray, width: int, x: int, y: int, rgb: tuple[int, int, int]) -> None:
    if x < 0 or y < 0 or x >= width:
        return
    index = (y * width + x) * 3
    if 0 <= index < len(pixels) - 2:
        pixels[index:index + 3] = bytes(rgb)


def fill_rect(
    pixels: bytearray,
    width: int,
    height: int,
    x0: int,
    y0: int,
    x1: int,
    y1: int,
    rgb: tuple[int, int, int],
) -> None:
    for y in range(max(0, y0), min(height, y1)):
        row = y * width * 3
        for x in range(max(0, x0), min(width, x1)):
            pixels[row + x * 3:row + x * 3 + 3] = bytes(rgb)


def draw_text(
    pixels: bytearray,
    width: int,
    height: int,
    x: int,
    y: int,
    text: str,
    rgb: tuple[int, int, int],
    scale: int = 3,
) -> None:
    cursor = x
    for char in text.upper()[:42]:
        glyph = FONT.get(char, FONT[" "])
        glyph_width = len(glyph[0])
        for gy, row in enumerate(glyph):
            for gx, bit in enumerate(row):
                if bit == "1":
                    fill_rect(
                        pixels,
                        width,
                        height,
                        cursor + gx * scale,
                        y + gy * scale,
                        cursor + (gx + 1) * scale,
                        y + (gy + 1) * scale,
                        rgb,
                    )
        cursor += (glyph_width + 1) * scale


def write_png(path: Path, label: str, subtitle: str, palette: tuple[tuple[int, int, int], ...]) -> None:
    width, height = 480, 270
    pixels = bytearray(width * height * 3)
    for y in range(height):
        for x in range(width):
            t = (x + y) / (width + height)
            base = palette[0] if t < 0.5 else palette[1]
            pixels[(y * width + x) * 3:(y * width + x) * 3 + 3] = bytes(base)
    fill_rect(pixels, width, height, 28, 28, width - 28, height - 28, (248, 248, 242))
    fill_rect(pixels, width, height, 42, 54, width - 42, 150, palette[2])
    fill_rect(pixels, width, height, 66, 170, 150, 220, palette[0])
    fill_rect(pixels, width, height, 166, 170, 250, 220, palette[1])
    fill_rect(pixels, width, height, 266, 170, 414, 220, palette[2])
    draw_text(pixels, width, height, 58, 82, label, (30, 36, 40), scale=4)
    draw_text(pixels, width, height, 58, 228, "SYNTHETIC DEMO", (30, 36, 40), scale=2)
    if subtitle:
        draw_text(pixels, width, height, 58, 118, subtitle, (30, 36, 40), scale=2)

    raw = b"".join(b"\x00" + pixels[y * width * 3:(y + 1) * width * 3] for y in range(height))
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    data = b"\x89PNG\r\n\x1a\n"
    data += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    data += chunk(b"IDAT", zlib.compress(raw, level=9))
    data += chunk(b"IEND", b"")
    path.write_bytes(data)


def write_pdf(path: Path, title: str, lines: list[str]) -> None:
    escaped_lines = [line.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)") for line in lines]
    stream_lines = ["BT", "/F1 12 Tf", "50 760 Td", f"({title}) Tj"]
    for line in escaped_lines:
        stream_lines.extend(["0 -18 Td", f"({line}) Tj"])
    stream_lines.append("ET")
    stream = "\n".join(stream_lines).encode("ascii")
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        b"<< /Length " + str(len(stream)).encode("ascii") + b" >>\nstream\n" + stream + b"\nendstream",
    ]
    content = bytearray(b"%PDF-1.4\n")
    offsets = [0]
    for i, obj in enumerate(objects, start=1):
        offsets.append(len(content))
        content.extend(f"{i} 0 obj\n".encode("ascii"))
        content.extend(obj)
        content.extend(b"\nendobj\n")
    xref_offset = len(content)
    content.extend(f"xref\n0 {len(objects) + 1}\n".encode("ascii"))
    content.extend(b"0000000000 65535 f \n")
    for offset in offsets[1:]:
        content.extend(f"{offset:010d} 00000 n \n".encode("ascii"))
    content.extend(
        f"trailer << /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref_offset}\n%%EOF\n".encode("ascii")
    )
    path.write_bytes(content)


def write_wav(path: Path, duration: float, frequency: float = 440.0) -> None:
    sample_rate = 8_000
    frames = int(sample_rate * min(duration, 2.0))
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(sample_rate)
        for i in range(frames):
            sample = int(1800 * math.sin(2 * math.pi * frequency * i / sample_rate))
            output.writeframes(struct.pack("<h", sample))


def write_mp4_placeholder(path: Path, label: str) -> None:
    # This is a tiny deterministic ISO BMFF-like placeholder. It is enough for
    # the current app to exercise file existence and video-type handling; local
    # thumbnail generation may fail, which is documented in the fixture README.
    ftyp_payload = b"isom\x00\x00\x02\x00isomiso2mp41"
    free_payload = f"Synthetic demo video placeholder: {label}\n".encode("ascii")
    data = struct.pack(">I4s", len(ftyp_payload) + 8, b"ftyp") + ftyp_payload
    data += struct.pack(">I4s", len(free_payload) + 8, b"free") + free_payload
    path.write_bytes(data)


def write_media_files() -> list[dict]:
    palette = ((107, 145, 122), (238, 190, 96), (139, 189, 213))
    manifest = []
    for filename, meta in MEDIA_LIBRARY.items():
        rel_path = meta.get("path")
        available = bool(meta.get("available"))
        if not rel_path:
            manifest.append({**meta, "filename": filename, "created": False})
            continue
        path = FIXTURE_ROOT / rel_path
        path.parent.mkdir(parents=True, exist_ok=True)
        if not available:
            manifest.append({**meta, "filename": filename, "created": False})
            continue
        kind = meta["kind"]
        if kind in {"photo", "sticker", "status_photo", "wallpaper"}:
            write_png(path, meta["label"], meta.get("caption", ""), palette)
            if kind == "wallpaper":
                shutil.copyfile(path, FIXTURE_ROOT / "current_wallpaper.jpg")
        elif kind == "document":
            write_pdf(
                path,
                meta["label"],
                [
                    "Synthetic demo fixture.",
                    "DEMO ONLY. Not a real ticket, receipt, document, or private message.",
                    meta.get("caption", ""),
                    "Fictional reference: DEMO-ORDER-042.",
                ],
            )
        elif kind in {"voice", "audio"}:
            write_wav(path, float(meta.get("duration", 2)), frequency=360.0 + len(filename))
        elif kind in {"video", "video_message"}:
            write_mp4_placeholder(path, meta["label"])
        manifest.append({**meta, "filename": filename, "created": available})
    return manifest


def lines_to_messages(chat: Chat, start: datetime, sender_lines: list[tuple[str, str, dict | None]]) -> None:
    for index, (sender, text, options) in enumerate(sender_lines):
        options = options or {}
        timestamp = options.get("timestamp") or (start + timedelta(minutes=index))
        media_key = options.get("media_key")
        media_meta = MEDIA_LIBRARY.get(media_key or "", {})
        chat.messages.append(
            Message(
                stable_id=f"{chat.key}-{len(chat.messages) + 1:03d}",
                chat_key=chat.key,
                timestamp=timestamp,
                sender=sender,
                text=text,
                message_type=options.get("message_type", 0),
                media_key=media_key,
                media_available=media_meta.get("available", True),
                expected_missing_label=media_meta.get("expected_missing_label"),
                latitude=options.get("latitude"),
                longitude=options.get("longitude"),
                duration=options.get("duration") or media_meta.get("duration"),
                group_event_type=options.get("group_event_type"),
            )
        )


def parse_demo_timestamp(value: str) -> datetime:
    return datetime.fromisoformat(value).replace(tzinfo=timezone.utc)


def build_chats() -> list[Chat]:
    chats = [
        Chat("c001", "Maya Chen", "one-to-one", CHARACTERS["maya"]["jid"], ["alex", "maya"]),
        Chat("c002", "Samir Patel", "one-to-one", CHARACTERS["samir"]["jid"], ["alex", "samir"]),
        Chat("c003", "Nina Rossi", "one-to-one", CHARACTERS["nina"]["jid"], ["alex", "nina"]),
        Chat("c004", "Theo Martin", "one-to-one", CHARACTERS["theo"]["jid"], ["alex", "theo"]),
        Chat("c005", "Elena Rivera", "one-to-one", CHARACTERS["elena"]["jid"], ["alex", "elena"]),
        Chat("c006", "Jules Meyer", "one-to-one", CHARACTERS["jules"]["jid"], ["alex", "jules"]),
        Chat("c007", "Priya Shah", "one-to-one", CHARACTERS["priya"]["jid"], ["alex", "priya"]),
        Chat("c008", "Green Corner Studio", "one-to-one", CHARACTERS["studio"]["jid"], ["alex", "studio"]),
        Chat("c009", "Lake Weekend", "group", "demo-lake-weekend@g.us", ["alex", "maya", "samir", "nina", "theo", "leo"]),
        Chat("c010", "Office Snacks", "group", "demo-office-snacks@g.us", ["alex", "theo", "samir", "maya"]),
        Chat("status", "Stories / Status", "status", "status@broadcast", ["alex", "maya", "samir"]),
    ]
    by_key = {chat.key: chat for chat in chats}

    def add(chat_id: str, rows: list[tuple]) -> None:
        chat = by_key[chat_id]
        for row in rows:
            stable_id, ts, sender, message_type, text, media_key, duration, latitude, longitude, group_event_type, missing_label = row
            media_meta = MEDIA_LIBRARY.get(media_key or "", {})
            display_text = text or media_meta.get("caption", "")
            if missing_label and missing_label not in display_text:
                display_text = f"{display_text} - {missing_label}"
            chat.messages.append(
                Message(
                    stable_id=stable_id,
                    chat_key=chat.key,
                    timestamp=parse_demo_timestamp(ts),
                    sender=sender,
                    text=display_text,
                    message_type=message_type,
                    media_key=media_key,
                    media_available=media_meta.get("available", True),
                    expected_missing_label=missing_label or media_meta.get("expected_missing_label"),
                    latitude=latitude,
                    longitude=longitude,
                    duration=duration or media_meta.get("duration"),
                    group_event_type=group_event_type,
                )
            )

    # tuple fields: id, timestamp, sender, message_type, text, media_key, duration, latitude, longitude, group_event_type, missing_label
    add("c001", [
        ("c001_m001", "2026-04-18T18:12:00", "alex", 0, "lake plan is becoming a whole production 😭", None, None, None, None, None, None),
        ("c001_m002", "2026-04-18T18:13:00", "maya", 0, "good. tiny weekend, huge committee", None, None, None, None, None, None),
        ("c001_m003", "2026-04-18T18:14:00", "alex", 0, "Sam is asking for a packing list PDF already", None, None, None, None, None, None),
        ("c001_m004", "2026-04-18T18:15:00", "maya", 0, "of course he is. PDF before personality", None, None, None, None, None, None),
        ("c001_m005", "2026-04-18T18:18:00", "maya", 1, "testing the picnic blanket situation", "photo_picnic_blanket.jpg", None, None, None, None, None),
        ("c001_m006", "2026-04-18T18:19:00", "alex", 0, "that blanket looks like it has survived three festivals", None, None, None, None, None, None),
        ("c001_m007", "2026-04-18T18:19:40", "maya", 0, "and it will survive Leo with snacks", None, None, None, None, None, None),
        ("c001_m008", "2026-04-19T09:02:00", "maya", 3, "Maya explains snack math for 18 seconds", "audio_maya_snack_math.wav", 18, None, None, None, None),
        ("c001_m009", "2026-04-19T09:06:00", "alex", 0, "I refuse to calculate snacks per person before coffee", None, None, None, None, None, None),
        ("c001_m010", "2026-04-19T09:08:00", "maya", 59, "Missed voice call", None, 0, None, None, None, None),
        ("c001_m011", "2026-04-19T09:09:00", "alex", 0, "sorry missed you, was brushing teeth", None, None, None, None, None, None),
        ("c001_m012", "2026-04-19T09:10:00", "maya", 0, "tragic. anyway I vote chips + fruit + one irresponsible cake", None, None, None, None, None, None),
        ("c001_m013", "2026-04-20T20:44:00", "alex", 0, "Nina might think she wasn't invited", None, None, None, None, None, None),
        ("c001_m014", "2026-04-20T20:45:00", "maya", 0, "oh no. add her before this becomes a documentary", None, None, None, None, None, None),
        ("c001_m015", "2026-04-21T12:21:00", "maya", 4, "instant video note placeholder", "video_instant_note.mp4", 4, None, None, None, None),
        ("c001_m016", "2026-04-21T12:22:00", "alex", 0, "why is that video just you pointing at a bag", None, None, None, None, None, None),
        ("c001_m017", "2026-04-21T12:23:00", "maya", 0, "because the bag contains the emergency snacks", None, None, None, None, None, None),
        ("c001_m018", "2026-04-24T21:30:00", "alex", 0, "tomorrow: lake, snacks, no drama", None, None, None, None, None, None),
        ("c001_m019", "2026-04-24T21:31:00", "maya", 0, "ambitious but beautiful", None, None, None, None, None, None),
    ])
    add("c002", [
        ("c002_m001", "2026-04-18T19:01:00", "samir", 0, "I made a simple plan. Simple by my standards.", None, None, None, None, None, None),
        ("c002_m002", "2026-04-18T19:03:00", "alex", 0, "that means at least two tables", None, None, None, None, None, None),
        ("c002_m003", "2026-04-18T19:04:00", "samir", 0, "Three, but one is emotional support.", None, None, None, None, None, None),
        ("c002_m004", "2026-04-18T19:08:00", "samir", 8, "PDF plan v1", "lake_weekend_plan.pdf", None, None, None, None, None),
        ("c002_m005", "2026-04-18T19:09:00", "alex", 0, "got the PDF", None, None, None, None, None, None),
        ("c002_m006", "2026-04-18T19:10:00", "alex", 0, "why does it have a risk column", None, None, None, None, None, None),
        ("c002_m007", "2026-04-18T19:11:00", "samir", 0, "Leo.", None, None, None, None, None, None),
        ("c002_m008", "2026-04-19T10:18:00", "samir", 1, "Updated meeting point screenshot", "photo_meeting_point.jpg", None, None, None, None, None),
        ("c002_m009", "2026-04-19T10:19:00", "samir", 0, "Tiny correction: boat tickets are 14:20, not 14:40.", None, None, None, None, None, None),
        ("c002_m010", "2026-04-19T10:21:00", "alex", 0, "noted. ticket time is 14:20", None, None, None, None, None, None),
        ("c002_m011", "2026-04-19T10:22:00", "samir", 0, "Please don't let Leo be in charge of timing.", None, None, None, None, None, None),
        ("c002_m012", "2026-04-20T08:30:00", "alex", 0, "Nina wasn't in the group yet. My bad.", None, None, None, None, None, None),
        ("c002_m013", "2026-04-20T08:31:00", "samir", 0, "Add her. The PDF has 6 people anyway.", None, None, None, None, None, None),
        ("c002_m014", "2026-04-20T08:32:00", "alex", 0, "the PDF knew before the group did", None, None, None, None, None, None),
        ("c002_m015", "2026-04-22T17:04:00", "samir", 0, "I updated the packing list section.", None, None, None, None, None, None),
        ("c002_m016", "2026-04-22T17:05:00", "alex", 0, "do we need a new PDF?", None, None, None, None, None, None),
        ("c002_m017", "2026-04-22T17:06:00", "samir", 0, "No. I am resisting version 2.", None, None, None, None, None, None),
        ("c002_m018", "2026-04-24T20:15:00", "samir", 0, "Final reminder: lake tickets, snacks, jacket, charger.", None, None, None, None, None, None),
    ])
    add("c003", [
        ("c003_m001", "2026-04-20T19:20:00", "nina", 0, "Wait, was everyone invited except me?", None, None, None, None, None, None),
        ("c003_m002", "2026-04-20T19:22:00", "alex", 0, "No no. I messed up the group invite.", None, None, None, None, None, None),
        ("c003_m003", "2026-04-20T19:22:40", "nina", 0, "I honestly thought it was a closed thing.", None, None, None, None, None, None),
        ("c003_m004", "2026-04-20T19:24:00", "alex", 0, "No, that's on me. I should've messaged you directly.", None, None, None, None, None, None),
        ("c003_m005", "2026-04-20T19:25:00", "nina", 0, "Okay but I was dramatic in my kitchen for like 12 minutes", None, None, None, None, None, None),
        ("c003_m006", "2026-04-20T19:26:00", "alex", 0, "valid. I deserve kitchen drama", None, None, None, None, None, None),
        ("c003_m007", "2026-04-20T19:28:00", "nina", 0, "Is there still space?", None, None, None, None, None, None),
        ("c003_m008", "2026-04-20T19:29:00", "alex", 0, "yes. Samir already counted you in the PDF somehow", None, None, None, None, None, None),
        ("c003_m009", "2026-04-20T19:29:30", "nina", 0, "the PDF is kinder than the group chat", None, None, None, None, None, None),
        ("c003_m010", "2026-04-20T19:31:00", "alex", 0, "adding you now", None, None, None, None, None, None),
        ("c003_m011", "2026-04-20T19:32:00", "nina", 0, "Okay, I'm coming if there's still cake.", None, None, None, None, None, None),
        ("c003_m012", "2026-04-20T19:33:00", "alex", 0, "Maya promised one irresponsible cake", None, None, None, None, None, None),
        ("c003_m013", "2026-04-20T19:34:00", "nina", 0, "I reserve the right to be dramatic for 10 minutes.", None, None, None, None, None, None),
        ("c003_m014", "2026-04-20T19:35:00", "alex", 0, "approved", None, None, None, None, None, None),
        ("c003_m015", "2026-04-21T08:15:00", "nina", 15, "tiny drama sticker", "sticker_tiny_drama.png", None, None, None, None, None),
        ("c003_m016", "2026-04-21T08:16:00", "alex", 0, "perfect summary", None, None, None, None, None, None),
    ])
    add("c004", [
        ("c004_m001", "2026-04-21T07:44:00", "theo", 0, "Station side entrance?", None, None, None, None, None, None),
        ("c004_m002", "2026-04-21T07:45:00", "alex", 0, "Yep. The one by the blue sign.", None, None, None, None, None, None),
        ("c004_m003", "2026-04-21T07:45:30", "theo", 0, "09:10?", None, None, None, None, None, None),
        ("c004_m004", "2026-04-21T07:46:00", "alex", 0, "09:10", None, None, None, None, None, None),
        ("c004_m005", "2026-04-21T07:47:00", "alex", 5, "Synthetic location for fixture only", None, None, 0.0, 0.0, None, None),
        ("c004_m006", "2026-04-21T07:49:00", "theo", 0, "Got it.", None, None, None, None, None, None),
        ("c004_m007", "2026-04-22T18:10:00", "theo", 0, "Office snacks chat is getting intense.", None, None, None, None, None, None),
        ("c004_m008", "2026-04-22T18:11:00", "alex", 0, "more intense than the lake ticket situation?", None, None, None, None, None, None),
        ("c004_m009", "2026-04-22T18:12:00", "theo", 0, "Different category of chaos.", None, None, None, None, None, None),
        ("c004_m010", "2026-04-24T19:55:00", "theo", 0, "I'll be there 09:10.", None, None, None, None, None, None),
    ])
    add("c005", [
        ("c005_m001", "2026-04-19T16:02:00", "elena", 0, "Are you doing something nice for your birthday weekend?", None, None, None, None, None, None),
        ("c005_m002", "2026-04-19T16:04:00", "alex", 0, "small lake thing with friends", None, None, None, None, None, None),
        ("c005_m003", "2026-04-19T16:05:00", "elena", 0, "That sounds lovely. Don't forget a jacket near the lake.", None, None, None, None, None, None),
        ("c005_m004", "2026-04-19T16:06:00", "alex", 0, "I knew jacket would arrive by message", None, None, None, None, None, None),
        ("c005_m005", "2026-04-19T16:08:00", "elena", 1, "Found this old birthday photo.", "photo_old_birthday.jpg", None, None, None, None, None),
        ("c005_m006", "2026-04-19T16:09:00", "alex", 0, "why was my haircut like that", None, None, None, None, None, None),
        ("c005_m007", "2026-04-19T16:10:00", "elena", 0, "You chose it proudly.", None, None, None, None, None, None),
        ("c005_m008", "2026-04-22T20:01:00", "elena", 3, "Elena says happy early birthday and reminds Alex to eat properly", "audio_elena_birthday_note.wav", 15, None, None, None, None),
        ("c005_m009", "2026-04-22T20:04:00", "alex", 0, "voice note received, food reminder accepted", None, None, None, None, None, None),
        ("c005_m010", "2026-04-22T20:06:00", "elena", 0, "And water.", None, None, None, None, None, None),
        ("c005_m011", "2026-04-24T12:30:00", "elena", 0, "Have a beautiful weekend tomorrow.", None, None, None, None, None, None),
        ("c005_m012", "2026-04-24T12:32:00", "alex", 0, "thanks ❤️", None, None, None, None, None, None),
    ])
    add("c006", [
        ("c006_m001", "2026-04-21T13:15:00", "alex", 0, "Hey, still selling the spare ticket?", None, None, None, None, None, None),
        ("c006_m002", "2026-04-21T13:48:00", "jules", 0, "Maybe, waiting on one person.", None, None, None, None, None, None),
        ("c006_m003", "2026-04-21T13:49:00", "alex", 0, "No worries. It's for the lake boat thing.", None, None, None, None, None, None),
        ("c006_m004", "2026-04-21T14:02:00", "jules", 1, "fake preview, not a real ticket", "photo_ticket_preview_fake.jpg", None, None, None, None, None),
        ("c006_m005", "2026-04-21T14:03:00", "jules", 0, "This is just the preview, not transferable yet.", None, None, None, None, None, None),
        ("c006_m006", "2026-04-21T14:05:00", "alex", 0, "All good. If it frees up, I can take it.", None, None, None, None, None, None),
        ("c006_m007", "2026-04-22T09:20:00", "jules", 8, "demo ticket note", "ticket_notes_demo.pdf", None, None, None, None, None),
        ("c006_m008", "2026-04-22T09:21:00", "alex", 0, "got the note", None, None, None, None, None, None),
        ("c006_m009", "2026-04-23T17:40:00", "alex", 0, "Any update on the ticket?", None, None, None, None, None, None),
        ("c006_m010", "2026-04-23T18:12:00", "jules", 0, "Still pending, sorry", None, None, None, None, None, None),
        ("c006_m011", "2026-04-24T09:05:00", "alex", 0, "No stress, I might have another option", None, None, None, None, None, None),
        ("c006_m012", "2026-04-24T11:30:00", "jules", 0, "I'll tell you if it clears", None, None, None, None, None, None),
    ])
    add("c007", [
        ("c007_m001", "2026-03-08T14:12:00", "priya", 0, "Still up for coffee sometime?", None, None, None, None, None, None),
        ("c007_m002", "2026-03-08T14:30:00", "alex", 0, "Yes, just chaotic week.", None, None, None, None, None, None),
        ("c007_m003", "2026-03-08T14:31:00", "priya", 0, "No stress.", None, None, None, None, None, None),
        ("c007_m004", "2026-04-23T10:03:00", "alex", 0, "Still owe you that coffee", None, None, None, None, None, None),
        ("c007_m005", "2026-04-23T10:08:00", "priya", 0, "After your lake weekend maybe", None, None, None, None, None, None),
    ])
    add("c008", [
        ("c008_m001", "2026-04-22T11:00:00", "studio", 0, "Hello Alex, your picnic basket order is ready for pickup.", None, None, None, None, None, None),
        ("c008_m002", "2026-04-22T11:02:00", "alex", 0, "Great, thank you. Is pickup possible Friday afternoon?", None, None, None, None, None, None),
        ("c008_m003", "2026-04-22T11:05:00", "studio", 0, "Yes. Reference: DEMO-ORDER-042.", None, None, None, None, None, None),
        ("c008_m004", "2026-04-22T11:06:00", "studio", 8, "Synthetic receipt PDF", "green_corner_receipt.pdf", None, None, None, None, None),
        ("c008_m005", "2026-04-22T11:08:00", "alex", 0, "Received the PDF receipt.", None, None, None, None, None, None),
        ("c008_m006", "2026-04-22T11:12:00", "alex", 66, "Outgoing voice call", None, 34, None, None, None, None),
        ("c008_m007", "2026-04-22T11:14:00", "studio", 0, "Confirmed: pickup window Friday 16:00-18:00.", None, None, None, None, None, None),
        ("c008_m008", "2026-04-22T11:15:00", "alex", 0, "Perfect", None, None, None, None, None, None),
        ("c008_m009", "2026-04-24T15:50:00", "studio", 6, "Order status changed to ready for pickup", None, None, None, None, None, None),
        ("c008_m010", "2026-04-24T16:02:00", "alex", 0, "On my way later today", None, None, None, None, None, None),
    ])
    add("c009", [
        ("c009_m001", "2026-04-18T20:00:00", "system", 6, "Alex Rivera created group \"Lake Weekend\"", None, None, None, None, 1, None),
        ("c009_m002", "2026-04-18T20:01:00", "system", 10, "Messages and calls are end-to-end encrypted. Synthetic demo notice.", None, None, None, None, 3, None),
        ("c009_m003", "2026-04-18T20:02:00", "alex", 0, "Welcome to the extremely official lake weekend chat", None, None, None, None, None, None),
        ("c009_m004", "2026-04-18T20:03:00", "maya", 0, "I already feel managed", None, None, None, None, None, None),
        ("c009_m005", "2026-04-18T20:04:00", "samir", 0, "I have prepared a PDF.", None, None, None, None, None, None),
        ("c009_m006", "2026-04-18T20:04:30", "leo", 0, "of course you have", None, None, None, None, None, None),
        ("c009_m007", "2026-04-18T20:05:00", "samir", 8, "Lake weekend PDF plan", "lake_weekend_plan.pdf", None, None, None, None, None),
        ("c009_m008", "2026-04-18T20:06:00", "theo", 0, "Thanks. I only read PDFs under social pressure.", None, None, None, None, None, None),
        ("c009_m009", "2026-04-18T20:07:00", "maya", 0, "same but I respect the font choice", None, None, None, None, None, None),
        ("c009_m010", "2026-04-18T20:08:00", "alex", 0, "Main thing: lake, picnic, optional boat, tiny birthday cake", None, None, None, None, None, None),
        ("c009_m011", "2026-04-18T20:09:00", "leo", 0, "define tiny", None, None, None, None, None, None),
        ("c009_m012", "2026-04-18T20:10:00", "maya", 0, "Leo no", None, None, None, None, None, None),
        ("c009_m013", "2026-04-18T20:11:00", "samir", 0, "Ticket question: I counted five boat tickets.", None, None, None, None, None, None),
        ("c009_m014", "2026-04-18T20:12:00", "alex", 0, "five? I thought six", None, None, None, None, None, None),
        ("c009_m015", "2026-04-18T20:13:00", "leo", 0, "I may have said I had one spare then forgot what spare means", None, None, None, None, None, None),
        ("c009_m016", "2026-04-18T20:14:00", "theo", 0, "That sentence reduced clarity.", None, None, None, None, None, None),
        ("c009_m017", "2026-04-18T20:15:00", "maya", 0, "ticket drama episode one", None, None, None, None, None, None),
        ("c009_m018", "2026-04-19T09:30:00", "samir", 0, "Correction: boat ticket time is 14:20, not 14:40.", None, None, None, None, None, None),
        ("c009_m019", "2026-04-19T09:31:00", "alex", 0, "14:20. Everybody please tattoo this mentally.", None, None, None, None, None, None),
        ("c009_m020", "2026-04-19T09:32:00", "maya", 0, "mentally washable tattoo", None, None, None, None, None, None),
        ("c009_m021", "2026-04-19T10:05:00", "theo", 5, "Synthetic meeting point for fixture only", None, None, 0.0, 0.0, None, None),
        ("c009_m022", "2026-04-19T10:06:00", "theo", 0, "Meet here at 09:10.", None, None, None, None, None, None),
        ("c009_m023", "2026-04-19T10:08:00", "leo", 0, "09:10 emotionally or literally", None, None, None, None, None, None),
        ("c009_m024", "2026-04-19T10:09:00", "samir", 0, "Literally.", None, None, None, None, None, None),
        ("c009_m025", "2026-04-19T12:40:00", "maya", 1, "not the actual lake but manifesting this energy", "photo_lake_view.jpg", None, None, None, None, None),
        ("c009_m026", "2026-04-19T12:41:00", "alex", 0, "that is aggressively peaceful", None, None, None, None, None, None),
        ("c009_m027", "2026-04-19T12:42:00", "leo", 0, "I can ruin the peace with snacks", None, None, None, None, None, None),
        ("c009_m028", "2026-04-19T12:43:00", "maya", 0, "you are not in charge of snacks", None, None, None, None, None, None),
        ("c009_m029", "2026-04-20T19:36:00", "system", 6, "Alex Rivera added Nina Rossi", None, None, None, None, 2, None),
        ("c009_m030", "2026-04-20T19:37:00", "nina", 0, "hello yes I have arrived from the forgotten dimension", None, None, None, None, None, None),
        ("c009_m031", "2026-04-20T19:38:00", "alex", 0, "public apology: I forgot to add Nina, not to invite Nina", None, None, None, None, None, None),
        ("c009_m032", "2026-04-20T19:39:00", "maya", 0, "we support dramatic entrances", None, None, None, None, None, None),
        ("c009_m033", "2026-04-20T19:40:00", "samir", 0, "Nina was already in the PDF headcount.", None, None, None, None, None, None),
        ("c009_m034", "2026-04-20T19:41:00", "nina", 0, "thank you PDF", None, None, None, None, None, None),
        ("c009_m035", "2026-04-20T19:42:00", "leo", 0, "the PDF is the real organizer", None, None, None, None, None, None),
        ("c009_m036", "2026-04-20T19:43:00", "alex", 0, "fair", None, None, None, None, None, None),
        ("c009_m037", "2026-04-21T08:00:00", "leo", 3, "Leo explains the ticket confusion", "audio_group_leo_explains.wav", 22, None, None, None, None),
        ("c009_m038", "2026-04-21T08:02:00", "theo", 0, "I understood less after the voice note.", None, None, None, None, None, None),
        ("c009_m039", "2026-04-21T08:03:00", "samir", 0, "Summary: we still need one ticket confirmation.", None, None, None, None, None, None),
        ("c009_m040", "2026-04-21T08:04:00", "nina", 0, "I can skip the boat if needed, but not the cake", None, None, None, None, None, None),
        ("c009_m041", "2026-04-21T08:05:00", "alex", 0, "Nobody skips cake", None, None, None, None, None, None),
        ("c009_m042", "2026-04-21T08:06:00", "maya", 0, "constitutional right", None, None, None, None, None, None),
        ("c009_m043", "2026-04-21T12:10:00", "maya", 2, "dramatic 3 second lake pan", "video_lake_pan.mp4", 3, None, None, None, None),
        ("c009_m044", "2026-04-21T12:12:00", "leo", 0, "cinema", None, None, None, None, None, None),
        ("c009_m045", "2026-04-21T15:30:00", "alex", 1, "boat sign, if it uploads", "photo_missing_boat_sign.jpg", None, None, None, None, "Media missing"),
        ("c009_m046", "2026-04-21T15:31:00", "alex", 0, "that photo may be missing on purpose for demo testing", None, None, None, None, None, None),
        ("c009_m047", "2026-04-21T15:32:00", "samir", 0, "Even the missing media has a test plan.", None, None, None, None, None, None),
        ("c009_m048", "2026-04-22T09:15:00", "theo", 0, "Weather says bring layers.", None, None, None, None, None, None),
        ("c009_m049", "2026-04-22T09:16:00", "system", 6, "System note: family reminder exists in another chat", None, None, None, None, None, None),
        ("c009_m050", "2026-04-22T09:17:00", "maya", 0, "Alex's mom already sent that spiritually", None, None, None, None, None, None),
        ("c009_m051", "2026-04-22T10:00:00", "samir", 0, "Final packing list: water, jacket, charger, snacks, ticket.", None, None, None, None, None, None),
        ("c009_m052", "2026-04-22T10:01:00", "leo", 0, "I can bring snacks", None, None, None, None, None, None),
        ("c009_m053", "2026-04-22T10:02:00", "maya", 0, "define bring", None, None, None, None, None, None),
        ("c009_m054", "2026-04-22T10:03:00", "leo", 0, "purchase with optimism", None, None, None, None, None, None),
        ("c009_m055", "2026-04-22T10:04:00", "nina", 0, "I trust Maya more", None, None, None, None, None, None),
        ("c009_m056", "2026-04-22T10:05:00", "alex", 0, "Maya snacks, Leo backup snacks", None, None, None, None, None, None),
        ("c009_m057", "2026-04-23T18:20:00", "samir", 4, "Possible spare ticket contact", "contact_jules.vcf", None, None, None, None, None),
        ("c009_m058", "2026-04-23T18:21:00", "alex", 0, "Already messaging Jules about the ticket", None, None, None, None, None, None),
        ("c009_m059", "2026-04-23T18:22:00", "theo", 0, "This archive will be 40% ticket discussion.", None, None, None, None, None, None),
        ("c009_m060", "2026-04-23T18:23:00", "maya", 0, "and 60% snacks", None, None, None, None, None, None),
        ("c009_m061", "2026-04-23T18:24:00", "nina", 0, "and 10% my dramatic entrance", None, None, None, None, None, None),
        ("c009_m062", "2026-04-23T18:25:00", "samir", 0, "That is 110%.", None, None, None, None, None, None),
        ("c009_m063", "2026-04-23T18:26:00", "leo", 0, "weekend energy", None, None, None, None, None, None),
        ("c009_m064", "2026-04-24T19:10:00", "alex", 0, "Tomorrow check: 09:10 station, 14:20 boat, PDF has details", None, None, None, None, None, None),
        ("c009_m065", "2026-04-24T19:11:00", "samir", 0, "Correct.", None, None, None, None, None, None),
        ("c009_m066", "2026-04-24T19:12:00", "maya", 0, "snacks packed", None, None, None, None, None, None),
        ("c009_m067", "2026-04-24T19:13:00", "nina", 0, "tiny drama packed", None, None, None, None, None, None),
        ("c009_m068", "2026-04-24T19:14:00", "leo", 0, "backup snacks spiritually packed", None, None, None, None, None, None),
        ("c009_m069", "2026-04-24T19:15:00", "theo", 0, "See you all tomorrow.", None, None, None, None, None, None),
    ])
    add("c010", [
        ("c010_m001", "2026-04-22T17:00:00", "system", 6, "Theo Martin created group \"Office Snacks\"", None, None, None, None, 1, None),
        ("c010_m002", "2026-04-22T17:01:00", "theo", 0, "Snack poll: salty / sweet / fruit / mystery box", None, None, None, None, None, None),
        ("c010_m003", "2026-04-22T17:02:00", "maya", 0, "salty", None, None, None, None, None, None),
        ("c010_m004", "2026-04-22T17:03:00", "samir", 0, "fruit, but I know this will lose", None, None, None, None, None, None),
        ("c010_m005", "2026-04-22T17:04:00", "alex", 0, "sweet", None, None, None, None, None, None),
        ("c010_m006", "2026-04-22T17:05:00", "theo", 0, "Current votes: salty 1, sweet 1, fruit 1, mystery 0", None, None, None, None, None, None),
        ("c010_m007", "2026-04-22T17:06:00", "maya", 0, "mystery box is how we lost trust last time", None, None, None, None, None, None),
        ("c010_m008", "2026-04-22T17:07:00", "alex", 0, "that was not a snack, that was a puzzle", None, None, None, None, None, None),
        ("c010_m009", "2026-04-22T17:08:00", "samir", 8, "Office snack rotation PDF", "office_snack_rotation.pdf", None, None, None, None, None),
        ("c010_m010", "2026-04-22T17:09:00", "maya", 0, "Samir made a snacks PDF. History repeats.", None, None, None, None, None, None),
        ("c010_m011", "2026-04-22T17:10:00", "samir", 0, "It is one page.", None, None, None, None, None, None),
        ("c010_m012", "2026-04-22T17:11:00", "theo", 1, "snack table prototype", "photo_snack_table.jpg", None, None, None, None, None),
        ("c010_m013", "2026-04-22T17:12:00", "alex", 0, "why does prototype sound so serious", None, None, None, None, None, None),
        ("c010_m014", "2026-04-22T17:13:00", "theo", 0, "Because snacks deserve governance.", None, None, None, None, None, None),
        ("c010_m015", "2026-04-22T17:14:00", "maya", 2, "unboxing the emergency snacks", "video_snack_unboxing.mp4", 5, None, None, None, None),
        ("c010_m016", "2026-04-22T17:15:00", "samir", 0, "Emergency snacks should be inventoried.", None, None, None, None, None, None),
        ("c010_m017", "2026-04-22T17:16:00", "alex", 0, "please do not inventory joy", None, None, None, None, None, None),
        ("c010_m018", "2026-04-22T17:17:00", "theo", 3, "Theo votes for salty snacks", "audio_office_vote.wav", 9, None, None, None, None),
        ("c010_m019", "2026-04-22T17:18:00", "maya", 0, "voice memo vote should count double", None, None, None, None, None, None),
        ("c010_m020", "2026-04-22T17:19:00", "samir", 0, "No.", None, None, None, None, None, None),
        ("c010_m021", "2026-04-23T09:10:00", "theo", 0, "Updated poll: salty 2, sweet 1, fruit 1", None, None, None, None, None, None),
        ("c010_m022", "2026-04-23T09:11:00", "alex", 0, "I accept democracy", None, None, None, None, None, None),
        ("c010_m023", "2026-04-23T09:12:00", "maya", 15, "snack vote sticker", "sticker_snack_vote.png", None, None, None, None, None),
        ("c010_m024", "2026-04-23T09:13:00", "samir", 0, "Please keep receipts if this uses the office budget.", None, None, None, None, None, None),
        ("c010_m025", "2026-04-23T09:14:00", "maya", 0, "the most Samir sentence", None, None, None, None, None, None),
        ("c010_m026", "2026-04-24T08:40:00", "theo", 0, "Snacks ordered.", None, None, None, None, None, None),
        ("c010_m027", "2026-04-24T08:41:00", "alex", 0, "office morale restored", None, None, None, None, None, None),
        ("c010_m028", "2026-04-24T08:42:00", "maya", 0, "until mystery box returns", None, None, None, None, None, None),
    ])
    add("status", [
        ("status_001", "2026-04-24T18:00:00", "alex", 1, "lake countdown", "status_alex_lake_countdown.jpg", None, None, None, None, None),
        ("status_002", "2026-04-24T18:30:00", "maya", 1, "snacks secured", "status_maya_snacks.jpg", None, None, None, None, None),
        ("status_003", "2026-04-24T19:00:00", "samir", 1, "PDF finally sent", "status_samir_pdf_done.jpg", None, None, None, None, None),
    ])

    return chats


def create_chat_storage(chats: list[Chat]) -> None:
    db_path = FIXTURE_ROOT / "ChatStorage.sqlite"
    connection = sqlite3.connect(db_path)
    cur = connection.cursor()
    cur.executescript(
        """
        PRAGMA journal_mode = DELETE;
        CREATE TABLE ZWACHATSESSION (
            Z_PK INTEGER PRIMARY KEY,
            ZCONTACTJID TEXT,
            ZCONTACTIDENTIFIER TEXT,
            ZPARTNERNAME TEXT,
            ZLASTMESSAGEDATE REAL,
            ZMESSAGECOUNTER INTEGER,
            ZLASTMESSAGE INTEGER
        );
        CREATE TABLE ZWAMESSAGE (
            Z_PK INTEGER PRIMARY KEY,
            ZCHATSESSION INTEGER,
            ZISFROMME INTEGER,
            ZFROMJID TEXT,
            ZPUSHNAME TEXT,
            ZTEXT TEXT,
            ZMESSAGEDATE REAL,
            ZMESSAGETYPE INTEGER,
            ZGROUPEVENTTYPE INTEGER,
            ZTOJID TEXT,
            ZGROUPMEMBER INTEGER,
            ZMEDIAITEM INTEGER
        );
        CREATE TABLE ZWAMEDIAITEM (
            Z_PK INTEGER PRIMARY KEY,
            ZMESSAGE INTEGER,
            ZMEDIALOCALPATH TEXT,
            ZTITLE TEXT,
            ZFILESIZE INTEGER,
            ZMEDIAORIGIN INTEGER,
            ZMEDIAURL TEXT,
            ZVCARDNAME TEXT,
            ZVCARDSTRING TEXT,
            ZLATITUDE REAL,
            ZLONGITUDE REAL,
            ZMOVIEDURATION REAL
        );
        CREATE TABLE ZWAGROUPMEMBER (
            Z_PK INTEGER PRIMARY KEY,
            ZCHATSESSION INTEGER,
            ZCONTACTNAME TEXT,
            ZFIRSTNAME TEXT,
            ZMEMBERJID TEXT
        );
        CREATE TABLE ZWAPROFILEPUSHNAME (
            Z_PK INTEGER PRIMARY KEY,
            ZJID TEXT,
            ZPUSHNAME TEXT
        );
        """
    )
    member_ids: dict[tuple[str, str], int] = {}
    member_pk = 1
    for chat_pk, chat in enumerate(chats, start=1):
        if chat.chat_type == "group":
            for participant_key in chat.participant_keys:
                character = CHARACTERS[participant_key]
                member_ids[(chat.key, participant_key)] = member_pk
                cur.execute(
                    "INSERT INTO ZWAGROUPMEMBER VALUES (?, ?, ?, ?, ?)",
                    (member_pk, chat_pk, character["name"], character["nickname"], character["jid"]),
                )
                member_pk += 1
    for i, character in enumerate(CHARACTERS.values(), start=1):
        cur.execute(
            "INSERT INTO ZWAPROFILEPUSHNAME VALUES (?, ?, ?)",
            (i, character["jid"], character["nickname"]),
        )

    message_pk = 1
    media_pk = 1
    manifest_messages: list[dict] = []
    for chat_pk, chat in enumerate(chats, start=1):
        last_message_id = message_pk + len(chat.messages) - 1
        latest = max(message.timestamp for message in chat.messages)
        cur.execute(
            "INSERT INTO ZWACHATSESSION VALUES (?, ?, ?, ?, ?, ?, ?)",
            (
                chat_pk,
                chat.jid,
                chat.jid,
                chat.title,
                apple_time(latest),
                len(chat.messages),
                last_message_id,
            ),
        )
        for message in chat.messages:
            sender_info = CHARACTERS.get(message.sender)
            is_system_sender = sender_info is None or message.sender == "system"
            is_from_me = 0 if chat.chat_type == "status" or is_system_sender else (1 if message.sender == "alex" else 0)
            member_id = member_ids.get((chat.key, message.sender)) if chat.chat_type == "group" else None
            from_jid = "status@broadcast" if chat.chat_type == "status" else (None if is_system_sender else sender_info["jid"])
            push_name = None if is_system_sender else sender_info["nickname"]
            media_item_id = media_pk if message.media_key else None
            cur.execute(
                "INSERT INTO ZWAMESSAGE VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    message_pk,
                    chat_pk,
                    is_from_me,
                    from_jid,
                    push_name,
                    message.text,
                    apple_time(message.timestamp),
                    message.message_type,
                    message.group_event_type,
                    chat.jid,
                    member_id,
                    media_item_id,
                ),
            )
            if message.media_key:
                media_meta = MEDIA_LIBRARY[message.media_key]
                local_path = media_meta.get("path")
                size = None
                if local_path and media_meta.get("available"):
                    size = (FIXTURE_ROOT / local_path).stat().st_size
                vcard_name = None
                vcard_string = None
                if media_meta["kind"] == "contact":
                    vcard_name = media_meta.get("vcard_name")
                    vcard_string = media_meta.get("vcard_string")
                media_origin = 1 if media_meta["kind"] == "voice" else 0
                cur.execute(
                    "INSERT INTO ZWAMEDIAITEM VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (
                        media_pk,
                        message_pk,
                        local_path,
                        media_meta.get("caption") or media_meta.get("label"),
                        size,
                        media_origin,
                        None,
                        vcard_name,
                        vcard_string,
                        message.latitude,
                        message.longitude,
                        message.duration,
                    ),
                )
                media_pk += 1
            elif message.message_type == 5:
                cur.execute(
                    "INSERT INTO ZWAMEDIAITEM VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    (
                        media_pk,
                        message_pk,
                        None,
                        message.text or "Synthetic location",
                        None,
                        0,
                        None,
                        None,
                        None,
                        message.latitude,
                        message.longitude,
                        None,
                    ),
                )
                media_item_id = media_pk
                cur.execute("UPDATE ZWAMESSAGE SET ZMEDIAITEM = ? WHERE Z_PK = ?", (media_pk, message_pk))
                media_pk += 1
            manifest_messages.append(
                {
                    "stable_message_id": message.stable_id,
                    "sqlite_message_id": message_pk,
                    "chat_id": chat.key,
                    "timestamp": message.timestamp.isoformat(),
                    "sender": sender_info["name"] if sender_info else "System",
                    "direction": "system" if is_system_sender else ("outgoing" if is_from_me else "incoming"),
                    "message_type": message.message_type,
                    "text_or_caption": message.text,
                    "media_filename": message.media_key,
                    "media_available": message.media_available,
                    "expected_missing_media_label": message.expected_missing_label,
                    "coordinates": None if message.latitude is None else [message.latitude, message.longitude],
                    "duration_seconds": message.duration,
                }
            )
            message_pk += 1
    connection.commit()
    connection.close()
    return manifest_messages


def create_contacts_v2() -> None:
    db_path = FIXTURE_ROOT / "ContactsV2.sqlite"
    connection = sqlite3.connect(db_path)
    cur = connection.cursor()
    cur.execute(
        """
        CREATE TABLE ZWAADDRESSBOOKCONTACT (
            Z_PK INTEGER PRIMARY KEY,
            ZWHATSAPPID TEXT,
            ZLID TEXT,
            ZIDENTIFIER TEXT,
            ZPHONENUMBER TEXT,
            ZLOCALIZEDPHONENUMBER TEXT,
            ZFULLNAME TEXT,
            ZGIVENNAME TEXT,
            ZLASTNAME TEXT,
            ZBUSINESSNAME TEXT,
            ZHIGHLIGHTEDNAME TEXT,
            ZUSERNAME TEXT
        )
        """
    )
    for i, character in enumerate(CHARACTERS.values(), start=1):
        given, _, last = character["name"].partition(" ")
        business = character["name"] if character["relationship"].startswith("fictional business") else None
        cur.execute(
            "INSERT INTO ZWAADDRESSBOOKCONTACT VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                i,
                character["jid"],
                f"demo_lid_{i:03d}@lid",
                character["jid"],
                character["phone"],
                character["phone"],
                character["name"],
                given,
                last or None,
                business,
                character["nickname"],
                character["nickname"].lower(),
            ),
        )
    connection.commit()
    connection.close()


def write_readme(validation: dict) -> None:
    readme = f"""# Synthetic Demo WhatsApp Archive

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
- birthday
- receipt

## Notes

Image placeholders are tiny generated PNG bitstreams stored with the requested
fixture filenames, including `.jpg` names, so the app can test image-path and
media-kind behavior without copyrighted or private images. Video placeholders are
small deterministic MP4-like files. They exercise existence, type inference, and
unavailable-thumbnail behavior; they are not intended to be real playable clips.

## Validation Summary

- Conversations: {validation["normal_conversations"]}
- One-to-one chats: {validation["one_to_one_chats"]}
- Group chats: {validation["group_chats"]}
- Status/story sessions: {validation["status_sessions"]}
- Messages: {validation["total_messages"]}
- Lake Weekend messages: {validation["lake_weekend_messages"]}
- Fixture size: {validation["fixture_size_bytes"]} bytes
"""
    (FIXTURE_ROOT / "README.md").write_text(readme, encoding="utf-8")


def validate_fixture(chats: list[Chat], media_manifest: list[dict]) -> dict:
    failures: list[str] = []
    warnings: list[str] = []
    chat_db = FIXTURE_ROOT / "ChatStorage.sqlite"
    contacts_db = FIXTURE_ROOT / "ContactsV2.sqlite"
    if not chat_db.exists():
        failures.append("ChatStorage.sqlite missing")
    if not contacts_db.exists():
        failures.append("ContactsV2.sqlite missing")

    connection = sqlite3.connect(chat_db)
    cur = connection.cursor()
    normal_conversations = cur.execute(
        "SELECT COUNT(*) FROM ZWACHATSESSION WHERE ZCONTACTJID <> 'status@broadcast'"
    ).fetchone()[0]
    one_to_one = cur.execute(
        "SELECT COUNT(*) FROM ZWACHATSESSION WHERE ZCONTACTJID NOT LIKE '%@g.us' AND ZCONTACTJID <> 'status@broadcast'"
    ).fetchone()[0]
    groups = cur.execute("SELECT COUNT(*) FROM ZWACHATSESSION WHERE ZCONTACTJID LIKE '%@g.us'").fetchone()[0]
    status_sessions = cur.execute("SELECT COUNT(*) FROM ZWACHATSESSION WHERE ZCONTACTJID = 'status@broadcast'").fetchone()[0]
    total_messages = cur.execute("SELECT COUNT(*) FROM ZWAMESSAGE").fetchone()[0]
    lake_messages = cur.execute(
        """
        SELECT COUNT(*)
        FROM ZWAMESSAGE m JOIN ZWACHATSESSION c ON c.Z_PK = m.ZCHATSESSION
        WHERE c.ZPARTNERNAME = 'Lake Weekend'
        """
    ).fetchone()[0]
    if normal_conversations != 10:
        failures.append(f"Expected 10 normal conversations, found {normal_conversations}")
    if one_to_one != 8:
        failures.append(f"Expected 8 one-to-one chats, found {one_to_one}")
    if groups != 2:
        failures.append(f"Expected 2 group chats, found {groups}")
    if status_sessions != 1:
        failures.append(f"Expected 1 status/story session, found {status_sessions}")
    if not 150 <= total_messages <= 250:
        failures.append(f"Expected 150-250 total messages, found {total_messages}")
    if lake_messages < 60:
        failures.append(f"Expected Lake Weekend to have at least 60 messages, found {lake_messages}")

    required_types = {
        "text": "m.ZMESSAGETYPE = 0 AND TRIM(COALESCE(m.ZTEXT, '')) <> ''",
        "photo": "m.ZMESSAGETYPE = 1",
        "video": "m.ZMESSAGETYPE = 2",
        "audio": "m.ZMESSAGETYPE = 3",
        "document": "m.ZMESSAGETYPE = 8",
        "location": "m.ZMESSAGETYPE = 5",
        "voice_call": "m.ZMESSAGETYPE IN (59, 66)",
        "system": "m.ZMESSAGETYPE IN (6, 10)",
        "status_story": "c.ZCONTACTJID = 'status@broadcast'",
        "contact_card": "m.ZMESSAGETYPE = 4 AND mi.ZVCARDSTRING IS NOT NULL",
        "sticker": "m.ZMESSAGETYPE = 15",
    }
    for label, predicate in required_types.items():
        count = cur.execute(
            f"""
            SELECT COUNT(*)
            FROM ZWAMESSAGE m
            LEFT JOIN ZWACHATSESSION c ON c.Z_PK = m.ZCHATSESSION
            LEFT JOIN ZWAMEDIAITEM mi ON mi.ZMESSAGE = m.Z_PK
            WHERE {predicate}
            """
        ).fetchone()[0]
        if count < 1:
            failures.append(f"Missing required message type: {label}")

    caption_count = cur.execute(
        """
        SELECT COUNT(*)
        FROM ZWAMESSAGE m JOIN ZWAMEDIAITEM mi ON mi.ZMESSAGE = m.Z_PK
        WHERE TRIM(COALESCE(m.ZTEXT, '')) <> ''
        """
    ).fetchone()[0]
    if caption_count < 1:
        failures.append("No media message has a caption")

    missing_refs = cur.execute(
        """
        SELECT mi.ZMEDIALOCALPATH, m.ZTEXT
        FROM ZWAMEDIAITEM mi JOIN ZWAMESSAGE m ON m.Z_PK = mi.ZMESSAGE
        WHERE mi.ZMEDIALOCALPATH LIKE '%missing%'
        """
    ).fetchall()
    if not missing_refs:
        failures.append("No intentionally missing media reference found")

    pdf_count = len(list((FIXTURE_ROOT / "Media").rglob("*.pdf")))
    if pdf_count < 2:
        failures.append(f"Expected at least two PDFs, found {pdf_count}")

    text_blob = "\n".join(
        row[0] or ""
        for row in cur.execute(
            """
            SELECT COALESCE(m.ZTEXT, '') || ' ' || COALESCE(mi.ZTITLE, '')
            FROM ZWAMESSAGE m LEFT JOIN ZWAMEDIAITEM mi ON mi.ZMESSAGE = m.Z_PK
            """
        )
    ).lower()
    for term in ["lake", "ticket", "pdf", "snacks", "birthday", "receipt"]:
        if term not in text_blob:
            failures.append(f"Search term missing: {term}")

    for rel_path, message_text in cur.execute(
        "SELECT mi.ZMEDIALOCALPATH, m.ZTEXT FROM ZWAMEDIAITEM mi JOIN ZWAMESSAGE m ON m.Z_PK = mi.ZMESSAGE WHERE mi.ZMEDIALOCALPATH IS NOT NULL"
    ):
        path = FIXTURE_ROOT / rel_path
        if "missing" in rel_path:
            if path.exists():
                failures.append(f"Intentionally missing media exists: {rel_path}")
            if "Media missing" not in (message_text or ""):
                failures.append(f"Missing media lacks expected label metadata: {rel_path}")
        elif not path.exists():
            failures.append(f"Available media reference does not exist: {rel_path}")

    all_files = [path for path in FIXTURE_ROOT.rglob("*") if path.is_file()]
    fixture_size = sum(path.stat().st_size for path in all_files)
    if fixture_size > MAX_FIXTURE_BYTES:
        failures.append(f"Fixture exceeds size limit: {fixture_size} bytes")

    suspicious_tokens = ["/Users/", "/var/mobile/", "AppDomainGroup-group.net.whatsapp"]
    for path in all_files:
        if path.suffix.lower() in {".sqlite", ".jpg", ".png", ".wav", ".mp4", ".pdf"}:
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        for token in suspicious_tokens:
            if token in text:
                failures.append(f"Suspicious real-data path token {token!r} in {path.relative_to(FIXTURE_ROOT)}")

    for path in all_files:
        if not path.resolve().is_relative_to(FIXTURE_ROOT.resolve()):
            failures.append(f"Generated file outside fixture root: {path}")

    for video_name in ["video_lake_pan.mp4", "video_snack_unboxing.mp4", "video_instant_note.mp4"]:
        warnings.append(f"{video_name} is a tiny placeholder, not a playable encoded video")

    connection.close()
    validation = {
        "passed": not failures,
        "failures": failures,
        "warnings": warnings,
        "normal_conversations": normal_conversations,
        "one_to_one_chats": one_to_one,
        "group_chats": groups,
        "status_sessions": status_sessions,
        "total_messages": total_messages,
        "lake_weekend_messages": lake_messages,
        "pdf_count": pdf_count,
        "fixture_size_bytes": fixture_size,
        "media_items": len(media_manifest),
        "available_media_files": sum(1 for item in media_manifest if item.get("created")),
        "missing_media_references": len(missing_refs),
    }
    return validation


def write_manifest(chats: list[Chat], media_manifest: list[dict], messages: list[dict], validation: dict) -> None:
    conversations = []
    for chat in chats:
        if chat.chat_type == "status":
            continue
        conversations.append(
            {
                "id": chat.key,
                "title": chat.title,
                "type": chat.chat_type,
                "jid": chat.jid,
                "participants": [CHARACTERS[key]["name"] for key in chat.participant_keys],
                "message_count": len(chat.messages),
            }
        )
    manifest = {
        "generated_at": "2026-04-26T00:00:00Z",
        "generator_version": GENERATOR_VERSION,
        "synthetic_notice": SYNTHETIC_NOTICE,
        "characters": CHARACTERS,
        "conversations": conversations,
        "status_story_session": {
            "title": "Stories / Status",
            "message_count": len(next(chat for chat in chats if chat.key == "status").messages),
            "detection": "status@broadcast",
        },
        "media_manifest": media_manifest,
        "messages": messages,
        "validation": validation,
        "expected_message_counts": {
            chat.key: len(chat.messages) for chat in chats
        },
    }
    (FIXTURE_ROOT / "demo_manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    recreate_fixture_root()
    media_manifest = write_media_files()
    chats = build_chats()
    messages = create_chat_storage(chats)
    create_contacts_v2()
    validation = validate_fixture(chats, media_manifest)
    write_readme(validation)
    write_manifest(chats, media_manifest, messages, validation)
    if not validation["passed"]:
        print(json.dumps(validation, indent=2))
        raise SystemExit(1)
    print(json.dumps(validation, indent=2))


if __name__ == "__main__":
    main()
