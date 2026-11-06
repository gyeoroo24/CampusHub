"""Lost and found reports share one shape; Kind names the table and columns for each."""
from dataclasses import dataclass


@dataclass(frozen=True)
class Kind:
    name: str          # "lost" or "found"
    table: str         # lost_reports
    photos: str        # lost_report_photos
    photo_fk: str      # lost_report_id
    when: str          # lost_at
    upload_kind: str   # lost_report_photo


LOST = Kind("lost", "lost_reports", "lost_report_photos", "lost_report_id", "lost_at", "lost_report_photo")
FOUND = Kind("found", "found_reports", "found_report_photos", "found_report_id", "found_at", "found_report_photo")
KINDS = {"lost": LOST, "found": FOUND}


def other_kind(kind: Kind) -> Kind:
    return FOUND if kind is LOST else LOST
