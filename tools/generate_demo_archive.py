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
    "photo_picnic_blanket.jpg": {
        "kind": "photo",
        "path": "Media/photo_picnic_blanket.jpg",
        "caption": "testing the picnic blanket situation",
        "label": "PICNIC BLANKET",
        "available": True,
    },
    "photo_meeting_point.jpg": {
        "kind": "photo",
        "path": "Media/photo_meeting_point.jpg",
        "caption": "Updated meeting point screenshot",
        "label": "DEMO MEETING MAP",
        "available": True,
    },
    "photo_old_birthday.jpg": {
        "kind": "photo",
        "path": "Media/photo_old_birthday.jpg",
        "caption": "Found this old birthday photo.",
        "label": "BIRTHDAY PHOTO CARD",
        "available": True,
    },
    "photo_lake_view.jpg": {
        "kind": "photo",
        "path": "Media/photo_lake_view.jpg",
        "caption": "not the actual lake but manifesting this energy",
        "label": "ABSTRACT LAKE",
        "available": True,
    },
    "photo_snack_table.jpg": {
        "kind": "photo",
        "path": "Media/photo_snack_table.jpg",
        "caption": "snack table prototype",
        "label": "SNACK TABLE",
        "available": True,
    },
    "photo_ticket_preview_fake.jpg": {
        "kind": "photo",
        "path": "Media/photo_ticket_preview_fake.jpg",
        "caption": "fake preview, not a real ticket",
        "label": "DEMO ONLY TICKET",
        "available": True,
    },
    "photo_group_selfie_placeholder.jpg": {
        "kind": "photo",
        "path": "Media/photo_group_selfie_placeholder.jpg",
        "caption": "group photo placeholder",
        "label": "ABSTRACT AVATARS",
        "available": True,
    },
    "photo_missing_boat_sign.jpg": {
        "kind": "photo",
        "path": "Media/photo_missing_boat_sign.jpg",
        "caption": "boat sign, if it uploads - Media missing expected",
        "label": "MISSING BOAT SIGN",
        "available": False,
        "expected_missing_label": "Media missing",
    },
    "photo_green_corner_basket.jpg": {
        "kind": "photo",
        "path": "Media/photo_green_corner_basket.jpg",
        "caption": "basket pickup shelf",
        "label": "BASKET PICKUP",
        "available": True,
    },
    "photo_message_layout_marker.jpg": {
        "kind": "photo",
        "path": "Message/Media/photo_message_layout_marker.jpg",
        "caption": "Message folder media layout sample",
        "label": "MESSAGE MEDIA",
        "available": True,
    },
    "sticker_snacks_demo.png": {
        "kind": "sticker",
        "path": "Media/sticker_snacks_demo.png",
        "caption": "snacks sticker placeholder",
        "label": "SNACKS STICKER",
        "available": True,
    },
    "video_lake_pan.mp4": {
        "kind": "video",
        "path": "Media/video_lake_pan.mp4",
        "caption": "dramatic 3 second lake pan",
        "label": "LAKE PAN VIDEO",
        "duration": 3,
        "available": True,
    },
    "video_snack_unboxing.mp4": {
        "kind": "video",
        "path": "Media/video_snack_unboxing.mp4",
        "caption": "unboxing the emergency snacks",
        "label": "SNACK VIDEO",
        "duration": 3,
        "available": True,
    },
    "video_instant_note.mp4": {
        "kind": "video_message",
        "path": "Media/video_instant_note.mp4",
        "caption": "instant video note placeholder",
        "label": "VIDEO NOTE",
        "duration": 5,
        "available": True,
    },
    "audio_maya_snack_math.wav": {
        "kind": "voice",
        "path": "Media/audio_maya_snack_math.wav",
        "caption": "Maya explains snack math for 18 seconds",
        "label": "MAYA SNACK MATH",
        "duration": 18,
        "available": True,
    },
    "audio_elena_birthday_note.wav": {
        "kind": "voice",
        "path": "Media/audio_elena_birthday_note.wav",
        "caption": "Elena says happy early birthday",
        "label": "ELENA BIRTHDAY NOTE",
        "duration": 14,
        "available": True,
    },
    "audio_group_leo_explains.wav": {
        "kind": "voice",
        "path": "Media/audio_group_leo_explains.wav",
        "caption": "Leo explains the ticket confusion",
        "label": "LEO TICKET NOTE",
        "duration": 12,
        "available": True,
    },
    "audio_office_vote.wav": {
        "kind": "audio",
        "path": "Media/audio_office_vote.wav",
        "caption": "Theo votes for salty snacks",
        "label": "OFFICE VOTE AUDIO",
        "duration": 7,
        "available": True,
    },
    "lake_weekend_plan.pdf": {
        "kind": "document",
        "path": "Media/lake_weekend_plan.pdf",
        "caption": "Uploading the PDF now.",
        "label": "LAKE WEEKEND PLAN",
        "available": True,
    },
    "green_corner_receipt.pdf": {
        "kind": "document",
        "path": "Media/green_corner_receipt.pdf",
        "caption": "Your picnic basket order is ready for pickup.",
        "label": "GREEN CORNER RECEIPT",
        "available": True,
    },
    "office_snack_rotation.pdf": {
        "kind": "document",
        "path": "Media/office_snack_rotation.pdf",
        "caption": "office snack rotation PDF",
        "label": "OFFICE SNACK ROTATION",
        "available": True,
    },
    "ticket_notes_demo.pdf": {
        "kind": "document",
        "path": "Media/ticket_notes_demo.pdf",
        "caption": "fake ticket transfer note, not valid",
        "label": "DEMO TICKET NOTE",
        "available": True,
    },
    "contact_green_corner.vcf": {
        "kind": "contact",
        "path": None,
        "caption": "Green Corner Studio contact card",
        "label": "GREEN CORNER CONTACT",
        "available": False,
    },
    "status_alex_lake_countdown.jpg": {
        "kind": "status_photo",
        "path": "Stories/status_alex_lake_countdown.jpg",
        "caption": "lake countdown",
        "label": "LAKE COUNTDOWN",
        "available": True,
    },
    "status_maya_snacks.jpg": {
        "kind": "status_photo",
        "path": "Stories/status_maya_snacks.jpg",
        "caption": "snacks secured",
        "label": "SNACKS SECURED",
        "available": True,
    },
    "status_samir_pdf_done.jpg": {
        "kind": "status_photo",
        "path": "Stories/status_samir_pdf_done.jpg",
        "caption": "PDF finally sent",
        "label": "PDF SENT",
        "available": True,
    },
    "wallpaper_demo_green_gradient.jpg": {
        "kind": "wallpaper",
        "path": "Wallpapers/wallpaper_demo_green_gradient.jpg",
        "caption": "synthetic wallpaper",
        "label": "DEMO WALLPAPER",
        "available": True,
    },
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


def build_chats() -> list[Chat]:
    chats = [
        Chat("maya", "Maya Chen", "one-to-one", CHARACTERS["maya"]["jid"], ["alex", "maya"]),
        Chat("samir", "Samir Patel", "one-to-one", CHARACTERS["samir"]["jid"], ["alex", "samir"]),
        Chat("nina", "Nina Rossi", "one-to-one", CHARACTERS["nina"]["jid"], ["alex", "nina"]),
        Chat("theo", "Theo Martin", "one-to-one", CHARACTERS["theo"]["jid"], ["alex", "theo"]),
        Chat("elena", "Elena Rivera", "one-to-one", CHARACTERS["elena"]["jid"], ["alex", "elena"]),
        Chat("jules", "Jules Meyer", "one-to-one", CHARACTERS["jules"]["jid"], ["alex", "jules"]),
        Chat("priya", "Priya Shah", "one-to-one", CHARACTERS["priya"]["jid"], ["alex", "priya"]),
        Chat("studio", "Green Corner Studio", "one-to-one", CHARACTERS["studio"]["jid"], ["alex", "studio"]),
        Chat("lake_weekend", "Lake Weekend", "group", "demo-lake-weekend@g.us", ["alex", "maya", "samir", "nina", "theo", "leo"]),
        Chat("office_snacks", "Office Snacks", "group", "demo-office-snacks@g.us", ["alex", "theo", "samir", "maya"]),
        Chat("status", "Stories / Status", "status", "status@broadcast", ["alex", "maya", "samir"]),
    ]
    by_key = {chat.key: chat for chat in chats}

    lines_to_messages(by_key["maya"], dt(18, 9, 0), [
        ("maya", "lake plan is becoming a whole production :')", None),
        ("alex", "A small production. Tasteful. With snacks.", None),
        ("maya", "I am bringing chips unless Leo panic-buys six bags again", None),
        ("alex", "Please prevent snack chaos if you can.", None),
        ("maya", "No promises. Snack chaos is my brand in this fictional demo.", None),
        ("maya", "testing the picnic blanket situation", {"message_type": 1, "media_key": "photo_picnic_blanket.jpg"}),
        ("alex", "That blanket looks lake-ready.", None),
        ("maya", "Voice memo incoming because snack math needs nuance.", None),
        ("maya", "Maya explains snack math for 18 seconds", {"message_type": 3, "media_key": "audio_maya_snack_math.wav"}),
        ("alex", "I understood maybe half, which is enough.", None),
        ("maya", "Missed voice call", {"message_type": 59, "duration": 0}),
        ("alex", "Sorry, was comparing ticket times.", None),
        ("maya", "You compared times plural? There is one boat.", None),
        ("alex", "There are contingencies.", None),
        ("maya", "The lake does not require a contingency matrix.", None),
        ("alex", "It might if Leo controls snacks.", None),
        ("maya", "Fair. Add emergency cookies.", None),
        ("maya", "instant video note placeholder", {"message_type": 4, "media_key": "video_instant_note.mp4"}),
        ("alex", "Saved for future snack training.", None),
        ("maya", "Sticker response.", {"message_type": 15, "media_key": "sticker_snacks_demo.png"}),
        ("alex", "I accept the sticker ruling.", None),
    ])

    lines_to_messages(by_key["samir"], dt(18, 11, 0), [
        ("samir", "Uploading the PDF now.", {"message_type": 8, "media_key": "lake_weekend_plan.pdf"}),
        ("alex", "Got it. PDF title is very official.", None),
        ("samir", "It has a packing list and a ticket section.", None),
        ("alex", "You made the lake weekend sound like a conference.", None),
        ("samir", "Conferences have working schedules.", None),
        ("samir", "Updated meeting point screenshot", {"message_type": 1, "media_key": "photo_meeting_point.jpg"}),
        ("alex", "The map labels are synthetic but useful.", None),
        ("samir", "Tiny correction: boat tickets are 14:20, not 14:40.", None),
        ("alex", "Updating my overplanned lake notes.", None),
        ("samir", "Please don't let Leo be in charge of timing.", None),
        ("alex", "He is in charge of vibes and maybe snacks.", None),
        ("samir", "That is already too much responsibility.", None),
        ("alex", "Do we need printed tickets?", None),
        ("samir", "No. Just the fake demo ticket count in the PDF.", None),
        ("alex", "Adding sunscreen to the list.", None),
        ("samir", "Add water too. People forget obvious things.", None),
        ("alex", "Maya says emergency cookies.", None),
        ("samir", "Approved, but label them emergency snacks.", None),
        ("alex", "Anything else before I send the group summary?", None),
        ("samir", "Mention PDF, ticket time, lake meeting point, and snacks.", None),
    ])

    lines_to_messages(by_key["nina"], dt(19, 14, 0), [
        ("nina", "Wait, was everyone invited except me?", None),
        ("alex", "No, that is on me. I should have messaged you directly.", None),
        ("nina", "I honestly thought it was a closed thing.", None),
        ("alex", "It was not closed. I just got tangled in the lake planning thread.", None),
        ("nina", "So the lake exists and I was just orbiting outside it.", None),
        ("alex", "Accurate but accidental.", None),
        ("nina", "I reserve the right to be dramatic for 10 minutes.", None),
        ("alex", "Granted. Full dramatic window approved.", None),
        ("nina", "Okay, I am coming if there is still space.", None),
        ("alex", "There is space. I will add you to Lake Weekend.", None),
        ("nina", "Good. I can bring fruit so it is not all snacks.", None),
        ("alex", "Maya will pretend fruit is decorative.", None),
        ("nina", "Maya can fight a grape.", None),
        ("alex", "This invite recovery is going better than expected.", None),
        ("nina", "Because I am warm and reasonable after exactly 10 minutes.", None),
        ("alex", "Timer respected.", None),
        ("nina", "Send the ticket details when you can.", None),
        ("alex", "Will do. Sorry again about the invite.", None),
    ])

    lines_to_messages(by_key["theo"], dt(20, 8, 30), [
        ("theo", "Station side entrance?", None),
        ("alex", "Yep. The one by the blue sign.", None),
        ("theo", "09:10?", None),
        ("alex", "I will be there 09:10.", None),
        ("theo", "Demo Station Side Entrance", {"message_type": 5, "latitude": 47.0001, "longitude": 8.0001}),
        ("alex", "Coordinates are synthetic, label is enough.", None),
        ("theo", "Good. Then lake transfer at 09:25.", None),
        ("alex", "Samir will like that precision.", None),
        ("theo", "He sent a PDF.", None),
        ("alex", "Of course he did.", None),
        ("theo", "Bring light bag.", None),
        ("alex", "And snacks?", None),
    ])

    lines_to_messages(by_key["elena"], dt(20, 18, 0), [
        ("elena", "Don't forget a jacket near the lake.", None),
        ("alex", "I know, Mom.", None),
        ("elena", "You say that and then call cold.", None),
        ("alex", "Fair evidence.", None),
        ("elena", "Found this old birthday photo.", {"message_type": 1, "media_key": "photo_old_birthday.jpg"}),
        ("alex", "That birthday photo is adorable and very synthetic.", None),
        ("elena", "Synthetic or not, you still looked serious about cake.", None),
        ("alex", "Cake requires focus.", None),
        ("elena", "Elena says happy early birthday", {"message_type": 3, "media_key": "audio_elena_birthday_note.wav"}),
        ("alex", "I listened. I will eat properly.", None),
        ("elena", "Good. Take a photo at the lake.", None),
        ("alex", "I will send a photo if the weather cooperates.", None),
        ("elena", "And text me when you arrive.", None),
        ("alex", "Promise.", None),
        ("elena", "Have fun with your friends.", None),
        ("alex", "Thanks. Jacket is packed.", None),
    ])

    lines_to_messages(by_key["jules"], dt(21, 10, 0), [
        ("alex", "Still selling the spare ticket?", None),
        ("jules", "Maybe, waiting on one person.", None),
        ("alex", "No rush, just checking before the lake plan locks.", None),
        ("jules", "fake preview, not a real ticket", {"message_type": 1, "media_key": "photo_ticket_preview_fake.jpg"}),
        ("alex", "Thanks. The preview says DEMO ONLY, perfect.", None),
        ("jules", "It is not valid for anything, obviously.", None),
        ("alex", "Can you send the ticket note too?", None),
        ("jules", "fake ticket transfer note, not valid", {"message_type": 8, "media_key": "ticket_notes_demo.pdf"}),
        ("alex", "Got the PDF. Still unresolved then?", None),
        ("jules", "Yes, waiting on a reply.", None),
        ("alex", "Okay. I will not count it yet.", None),
        ("jules", "Good plan.", None),
        ("alex", "Ping me when you know.", None),
        ("jules", "Will do.", None),
    ])

    lines_to_messages(by_key["priya"], dt(22, 17, 0), [
        ("priya", "Still up for coffee sometime?", {"timestamp": old_dt()}),
        ("alex", "Yes, just chaotic week.", None),
        ("priya", "No stress.", None),
        ("alex", "Maybe after the lake weekend?", None),
        ("priya", "Works. Coffee after chaos.", None),
        ("alex", "Deal.", None),
    ])

    lines_to_messages(by_key["studio"], dt(22, 12, 0), [
        ("studio", "Your picnic basket order is ready for pickup.", {"message_type": 8, "media_key": "green_corner_receipt.pdf"}),
        ("alex", "Great, thanks. Is the receipt attached?", None),
        ("studio", "Reference: DEMO-ORDER-042", None),
        ("studio", "basket pickup shelf", {"message_type": 1, "media_key": "photo_green_corner_basket.jpg"}),
        ("alex", "I will stop by before the lake trip.", None),
        ("studio", "Pickup window is fictional and flexible.", None),
        ("alex", "Outgoing voice call, 00:34", {"message_type": 66, "duration": 34}),
        ("studio", "Appointment note saved for the picnic basket.", None),
        ("alex", "Please include napkins.", None),
        ("studio", "Added napkins to the demo order.", None),
        ("alex", "PDF receipt has everything I need.", None),
        ("studio", "Message folder media layout sample", {"message_type": 1, "media_key": "photo_message_layout_marker.jpg"}),
        ("studio", "Thank you for using Green Corner Studio.", None),
    ])

    lake_lines = [
        ("alex", "Group created by Alex.", {"message_type": 6, "group_event_type": 1}),
        ("alex", "Welcome to Lake Weekend. This is a synthetic demo group.", None),
        ("maya", "I am here for snacks and gentle chaos.", None),
        ("samir", "I am here for the PDF and ticket timing.", None),
        ("theo", "I am here for station logistics.", None),
        ("leo", "I am here by accident but I brought optimism.", None),
        ("samir", "Uploading the PDF now.", {"message_type": 8, "media_key": "lake_weekend_plan.pdf"}),
        ("alex", "Please read the lake PDF before inventing plans.", None),
        ("leo", "Does the PDF cover snacks?", None),
        ("maya", "It better. Snacks are core infrastructure.", None),
        ("samir", "Ticket count is four confirmed, one pending.", None),
        ("theo", "Station side entrance at 09:10.", None),
        ("theo", "Demo Station Side Entrance", {"message_type": 5, "latitude": 47.0001, "longitude": 8.0001}),
        ("alex", "Coordinates are synthetic; follow the fake blue sign.", None),
        ("maya", "not the actual lake but manifesting this energy", {"message_type": 1, "media_key": "photo_lake_view.jpg"}),
        ("leo", "I can hear this photo demanding snacks.", None),
        ("maya", "Green Corner Studio contact card", {"message_type": 4, "media_key": "contact_green_corner.vcf"}),
        ("alex", "Useful. That is the picnic basket contact.", None),
        ("samir", "Reminder: boat tickets are 14:20.", None),
        ("alex", "Samir corrected 14:40 to 14:20 earlier.", None),
        ("leo", "So 14:30?", None),
        ("samir", "No. 14:20.", None),
        ("maya", "Leo has entered the ticket fog.", None),
        ("alex", "I am adding Nina now.", {"message_type": 6, "group_event_type": 2}),
        ("nina", "Hi. Was I forgotten or dramatically delayed?", None),
        ("alex", "Dramatically delayed by my bad invite handling. Sorry.", None),
        ("nina", "Okay, I am here and mildly dramatic.", None),
        ("maya", "Welcome. We have snacks diplomacy.", None),
        ("nina", "I can bring fruit and emotional balance.", None),
        ("leo", "Fruit is just quiet snacks.", None),
        ("samir", "Security notice: messages are end-to-end encrypted in this synthetic demo.", {"message_type": 10, "group_event_type": 3}),
        ("theo", "Back to logistics. Train buffer is 12 minutes.", None),
        ("alex", "I like a buffer.", None),
        ("maya", "You like three buffers stacked in a trench coat.", None),
        ("samir", "Ticket PDF says meet 09:10, depart 09:25.", None),
        ("leo", "I may have told Jules we needed six tickets.", None),
        ("alex", "Why six?", None),
        ("leo", "I counted snacks as a person.", None),
        ("nina", "Honestly snacks deserve representation.", None),
        ("samir", "We need five tickets plus one pending spare, not six confirmed.", None),
        ("maya", "Leo explains the ticket confusion", {"message_type": 3, "media_key": "audio_group_leo_explains.wav"}),
        ("alex", "That voice note somehow made it less clear.", None),
        ("theo", "I will book the transport for five.", None),
        ("samir", "Good. PDF revision not needed.", None),
        ("maya", "group photo placeholder", {"message_type": 1, "media_key": "photo_group_selfie_placeholder.jpg"}),
        ("nina", "Everyone looks like abstract blobs. Accurate.", None),
        ("leo", "dramatic 3 second lake pan", {"message_type": 2, "media_key": "video_lake_pan.mp4"}),
        ("alex", "The video placeholder may not thumbnail, but the row should load.", None),
        ("samir", "Please do not debug video at the station.", None),
        ("maya", "boat sign, if it uploads - Media missing expected", {"message_type": 1, "media_key": "photo_missing_boat_sign.jpg"}),
        ("alex", "Good missing media test. The app should show a placeholder.", None),
        ("nina", "I am no longer annoyed, for the record.", None),
        ("maya", "Resolution achieved. Snacks remain unresolved.", None),
        ("leo", "I can bring chips.", None),
        ("samir", "You said that last time and brought six identical bags.", None),
        ("leo", "Consistency is a virtue.", None),
        ("alex", "Bring two chips, Nina fruit, Maya cookies.", None),
        ("theo", "I will bring water.", None),
        ("samir", "I will bring printed backup of the PDF.", None),
        ("maya", "The PDF has become a character.", None),
        ("nina", "Can the PDF carry snacks?", None),
        ("alex", "No, but it can list snacks.", None),
        ("leo", "I vote mystery snacks.", None),
        ("samir", "No mystery near tickets.", None),
        ("theo", "Weather looks mild in the fictional forecast.", None),
        ("maya", "Lake plan, ticket plan, snack plan. We are powerful.", None),
        ("alex", "Final summary: station 09:10, lake boat ticket 14:20, snacks assigned.", None),
        ("nina", "And invite drama resolved.", None),
        ("leo", "And I am not in charge of timing.", None),
        ("samir", "Correct.", None),
        ("maya", "Emergency cookies are packed.", None),
        ("alex", "Thanks everyone. This demo group is ready.", None),
    ]
    lines_to_messages(by_key["lake_weekend"], dt(23, 9, 0), lake_lines)

    office_lines = [
        ("theo", "Snack poll: salty / sweet / fruit / mystery box", None),
        ("maya", "Mystery box is how we got office raisins.", None),
        ("samir", "Current votes: salty 2, sweet 1, fruit 1.", None),
        ("alex", "I vote salty snacks but support fruit diplomacy.", None),
        ("maya", "snack table prototype", {"message_type": 1, "media_key": "photo_snack_table.jpg"}),
        ("theo", "Looks efficient.", None),
        ("samir", "office snack rotation PDF", {"message_type": 8, "media_key": "office_snack_rotation.pdf"}),
        ("alex", "A PDF for snacks is very on theme.", None),
        ("maya", "The office has become Samir's second lake.", None),
        ("samir", "The PDF prevents snack drift.", None),
        ("theo", "Theo votes for salty snacks", {"message_type": 3, "media_key": "audio_office_vote.wav"}),
        ("alex", "Audio vote accepted.", None),
        ("maya", "unboxing the emergency snacks", {"message_type": 2, "media_key": "video_snack_unboxing.mp4"}),
        ("samir", "Video evidence is helpful.", None),
        ("theo", "Need labels.", None),
        ("alex", "Labels: salty, sweet, fruit, mystery.", None),
        ("maya", "Mystery should be renamed risk.", None),
        ("samir", "Poll update: salty 3, sweet 1, fruit 1, mystery 0.", None),
        ("theo", "Good.", None),
        ("alex", "Can we put PDF near shelf?", None),
        ("samir", "Yes, but not as decoration.", None),
        ("maya", "Everything is decoration if you commit.", None),
        ("theo", "I will bring clips.", None),
        ("alex", "Office snacks plan is calmer than lake snacks.", None),
        ("maya", "Only because Leo is absent.", None),
        ("samir", "Please keep it that way.", None),
        ("theo", "Basket from Green Corner could help.", None),
        ("alex", "Good idea. I have a receipt PDF from them.", None),
        ("maya", "Snack poll closing in five.", None),
        ("samir", "Final: salty wins. PDF updated.", None),
    ]
    lines_to_messages(by_key["office_snacks"], dt(24, 10, 0), office_lines)

    lines_to_messages(by_key["status"], dt(25, 8, 0), [
        ("alex", "lake countdown", {"message_type": 1, "media_key": "status_alex_lake_countdown.jpg"}),
        ("maya", "snacks secured", {"message_type": 1, "media_key": "status_maya_snacks.jpg"}),
        ("samir", "PDF finally sent", {"message_type": 1, "media_key": "status_samir_pdf_done.jpg"}),
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
            sender_info = CHARACTERS[message.sender]
            is_from_me = 0 if chat.chat_type == "status" else (1 if message.sender == "alex" else 0)
            member_id = member_ids.get((chat.key, message.sender)) if chat.chat_type == "group" else None
            from_jid = "status@broadcast" if chat.chat_type == "status" else sender_info["jid"]
            media_item_id = media_pk if message.media_key else None
            cur.execute(
                "INSERT INTO ZWAMESSAGE VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    message_pk,
                    chat_pk,
                    is_from_me,
                    from_jid,
                    sender_info["nickname"],
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
                    vcard_name = "Green Corner Studio"
                    vcard_string = (
                        "BEGIN:VCARD\nVERSION:3.0\nFN:Green Corner Studio\n"
                        "TEL:+15550108\nNOTE:Synthetic demo contact card\nEND:VCARD"
                    )
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
                    "sender": CHARACTERS[message.sender]["name"],
                    "direction": "outgoing" if is_from_me else "incoming",
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

This is a fully synthetic demo archive for WhatsApp Archiver.

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

Run the iOS viewer and tap `Try Demo Archive` on the archive home screen. The
Xcode app target bundles this synthetic fixture as `Demo Archive`, and opening
it does not occupy either real archive slot.

To test the manual Add flow, choose a real archive slot and select this
directory:

```text
test-fixtures/demo-archive/
```

Selecting the folder is preferred over selecting `ChatStorage.sqlite` directly
because media availability checks and `current_wallpaper.jpg` resolution use the
archive root.

The same folder can work on device if it is copied through Finder or Files and
then selected from the app. The fixture is bundled in Xcode builds only; GitHub
source alone is not a one-tap iPhone install path.

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

    pdf_count = len(list((FIXTURE_ROOT / "Media").glob("*.pdf")))
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
    for term in ["lake", "ticket", "pdf", "snacks"]:
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
