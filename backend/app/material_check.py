"""Checking a file uploaded to a course's shared materials repository before anyone else can get it.

Anyone signed in can share course materials, so every file is opened and checked on the server, not
trusted by its name or the type the browser claimed:

  Refused outright (the upload fails with the reason; the file is deleted):
    - a type we don't take (only PDF, Word, PowerPoint, Excel, text/CSV/Markdown, images and ZIP)
    - contents that don't match the claimed type (an .apk renamed .pdf: the first bytes give it away)
    - programs: Windows/Linux/macOS executables, Android apps (APK), Java archives, installers,
      scripts (.bat, .sh, .ps1, .vbs, .js ...), anywhere, including inside a ZIP
    - Office files with macros (vbaProject.bin inside a .docx/.pptx/.xlsx)
    - a ZIP bomb (a tiny file that unpacks to gigabytes) or an unreadable/corrupt archive
  Held for the course's moderators (uploaded, hidden from everyone but the uploader and moderators, and
  reported in the moderation queue as an automatic flag):
    - a password-protected ZIP or PDF, archives inside archives, or very many files in one ZIP
    - a PDF with embedded JavaScript, launch actions or attached files
    - a title or description that reads like leaked papers or exam help for sale, or gibberish
    - more than 10 uploads by one person in an hour (spam)
The size limit (100 MB) is enforced when the upload is signed (app/storage.py).
"""
import io
import re
import zipfile
from dataclasses import dataclass, field

MB = 1024 * 1024
MAX_ZIP_ENTRIES = 2000
MAX_ZIP_UNPACKED = 1024 * MB
MAX_ZIP_RATIO = 200
FLAG_ZIP_ENTRIES = 300
SPAM_PER_HOUR = 10

DANGEROUS_EXTENSIONS = {
    "apk", "aab", "xapk", "exe", "msi", "msp", "com", "scr", "pif", "cpl", "dll", "sys", "so", "dylib", "bin",
    "bat", "cmd", "ps1", "psm1", "vbs", "vbe", "js", "jse", "wsf", "wsh", "hta", "sh", "bash", "zsh", "csh",
    "jar", "class", "dex", "app", "dmg", "pkg", "deb", "rpm", "appimage", "iso", "img", "lnk", "reg", "inf",
    "docm", "dotm", "xlsm", "xltm", "xlam", "pptm", "potm", "ppam", "ipa", "run", "elf", "out",
}
ARCHIVE_EXTENSIONS = {"zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz"}

# What each allowed type must look like inside.
OFFICE_TYPES = {
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "word/",
    "application/vnd.openxmlformats-officedocument.presentationml.presentation": "ppt/",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "xl/",
}
TEXT_TYPES = {"text/plain", "text/csv", "text/markdown"}
IMAGE_MAGIC = {
    "image/jpeg": (b"\xff\xd8\xff",),
    "image/png": (b"\x89PNG\r\n\x1a\n",),
}

# Signatures of programs, whatever they're called.
_EXECUTABLE_MAGIC = (b"MZ", b"\x7fELF", b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe",
                     b"\xfe\xed\xfa\xce", b"\xfe\xed\xfa\xcf", b"dex\n", b"#!")

_SUSPICIOUS_TEXT = re.compile(
    r"\b(leaked?|leak|answer\s*keys?\s*(for\s*sale|available)|selling|for\s*sale|paid|buy\s+now|"
    r"(will|can)\s+(write|take|do)\s+(your|ur)\s+(exam|quiz|assignment)|proxy\s+(exam|attendance)|"
    r"whatsapp\s*\+?\d|telegram\s*@)\b", re.IGNORECASE)


class Rejected(ValueError):
    """The file can't be shared; the message says why, for the uploader."""


@dataclass
class CheckResult:
    flags: list[str] = field(default_factory=list)   # reasons to hold for a moderator; empty = fine


def _ext(name: str) -> str:
    return name.rsplit(".", 1)[-1].lower() if "." in name else ""


def _check_zip_entries(zf: zipfile.ZipFile, result: CheckResult, office: bool) -> None:
    infos = zf.infolist()
    if len(infos) > MAX_ZIP_ENTRIES:
        raise Rejected(f"The archive has {len(infos)} files; at most {MAX_ZIP_ENTRIES} are allowed.")
    unpacked = sum(i.file_size for i in infos)
    packed = max(1, sum(i.compress_size for i in infos))
    if unpacked > MAX_ZIP_UNPACKED or (unpacked > 50 * MB and unpacked / packed > MAX_ZIP_RATIO):
        raise Rejected("The archive unpacks to far more than its size (a ZIP bomb), so it can't be shared.")
    names = [i.filename for i in infos]
    lowered = [n.lower() for n in names]
    if "androidmanifest.xml" in lowered or "classes.dex" in lowered or any(n.endswith("/classes.dex") for n in lowered):
        raise Rejected("This is an Android app (APK). Apps can't be shared as course material.")
    if any(n == "meta-inf/manifest.mf" for n in lowered) and any(n.endswith(".class") for n in lowered):
        raise Rejected("This is a Java program (JAR). Programs can't be shared as course material.")
    if office and any(n.endswith("vbaproject.bin") for n in lowered):
        raise Rejected("This document contains macros. Save it without macros (.docx/.pptx/.xlsx) and upload again.")
    if not office:
        bad = sorted({n for n in names if _ext(n) in DANGEROUS_EXTENSIONS})
        if bad:
            shown = ", ".join(n.rsplit("/", 1)[-1] for n in bad[:3])
            raise Rejected(f"The archive contains programs or scripts ({shown}), which can't be shared.")
        if any(i.flag_bits & 0x1 for i in infos):
            result.flags.append("password-protected archive (its contents can't be checked)")
        nested = [n for n in names if _ext(n) in ARCHIVE_EXTENSIONS]
        if nested:
            result.flags.append(f"archive inside the archive ({nested[0].rsplit('/', 1)[-1]})")
        if len(infos) > FLAG_ZIP_ENTRIES:
            result.flags.append(f"{len(infos)} files in one archive")
        # Programs hidden under harmless names: look at the start of a few entries.
        for info in infos[:200]:
            if info.is_dir() or info.flag_bits & 0x1 or info.file_size < 4:
                continue
            with zf.open(info) as f:
                head = f.read(8)
            if head.startswith(_EXECUTABLE_MAGIC[:-1]):
                raise Rejected(f"{info.filename.rsplit('/', 1)[-1]} inside the archive is a program, which can't be shared.")


def check_material(data: bytes, content_type: str, file_name: str = "") -> CheckResult:
    """Raises Rejected, or returns the reasons (if any) to hold the file for a moderator."""
    result = CheckResult()
    head = data[:16]
    if _ext(file_name) in DANGEROUS_EXTENSIONS:
        raise Rejected(f".{_ext(file_name)} files are programs or macro documents and can't be shared.")
    if head.startswith(_EXECUTABLE_MAGIC):
        raise Rejected("This file is a program, not a document, so it can't be shared.")
    if content_type == "application/pdf":
        if not head.startswith(b"%PDF"):
            raise Rejected("This isn't really a PDF (its contents don't match). Upload the original file.")
        sample = data[:5 * MB] + data[-MB:]
        if re.search(rb"/(JavaScript|JS)\b", sample) or b"/Launch" in sample:
            result.flags.append("PDF with embedded JavaScript or launch actions")
        if b"/EmbeddedFile" in sample:
            result.flags.append("PDF with attached files")
        if b"/Encrypt" in sample:
            result.flags.append("password-protected PDF (its contents can't be checked)")
    elif content_type in OFFICE_TYPES or content_type == "application/zip":
        if not head.startswith(b"PK\x03\x04"):
            raise Rejected("This file's contents don't match its type. Upload the original file.")
        try:
            with zipfile.ZipFile(io.BytesIO(data)) as zf:
                office = content_type in OFFICE_TYPES
                if office and not any(n.startswith(OFFICE_TYPES[content_type]) for n in zf.namelist()):
                    raise Rejected("This file's contents don't match its type. Upload the original file.")
                _check_zip_entries(zf, result, office)
        except zipfile.BadZipFile as exc:
            raise Rejected("The file is damaged or isn't a real archive.") from exc
    elif content_type in IMAGE_MAGIC:
        if not head.startswith(IMAGE_MAGIC[content_type]):
            raise Rejected("This image's contents don't match its type. Upload the original file.")
    elif content_type == "image/webp":
        if not (head.startswith(b"RIFF") and head[8:12] == b"WEBP"):
            raise Rejected("This image's contents don't match its type. Upload the original file.")
    elif content_type == "image/heic":
        if head[4:8] != b"ftyp":
            raise Rejected("This image's contents don't match its type. Upload the original file.")
    elif content_type in TEXT_TYPES:
        if b"\x00" in data[:MB]:
            raise Rejected("This isn't a text file (it has binary data). Upload the original file.")
    else:
        raise Rejected(f"Files of type {content_type} can't be shared here.")
    return result


def text_flags(title: str, description: str | None) -> list[str]:
    """Reasons a title/description should be looked at: selling papers or exam help, contact details."""
    text = f"{title}\n{description or ''}"
    m = _SUSPICIOUS_TEXT.search(text)
    return [f'title or description mentions "{m.group(0).strip()}"'] if m else []
