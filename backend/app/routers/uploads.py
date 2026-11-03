"""Upload tickets: presigned S3 URLs the client uploads files to directly."""
from typing import Literal
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from ..auth import CurrentUser, current_user
from ..common import forbidden
from ..config import get_settings
from ..db import get_conn
from ..permissions import is_module_moderator
from ..storage import MB, PENDING_TAG, UPLOAD_KINDS, check_sha256_b64, new_object_key, presign_put

router = APIRouter(prefix="/uploads", tags=["Uploads"])


class UploadRequest(BaseModel):
    kind: Literal["listing_photo", "lost_report_photo", "found_report_photo", "course_material", "job_description",
                  "event_poster", "mess_menu"]
    content_type: str = Field(examples=["image/jpeg"])
    size_bytes: int = Field(gt=0)
    checksum_sha256: str = Field(description="Base64 of the file's SHA-256 digest (NFR-8)")
    course_id: UUID | None = Field(None, description="Required for course_material")


class UploadTicket(BaseModel):
    s3_key: str
    upload_url: str
    method: str = "PUT"
    headers: dict[str, str] = Field(description="Send exactly these headers with the PUT. The file must also be "
                                                "exactly size_bytes long (S3 checks Content-Length).")
    expires_in: int


@router.post("", response_model=UploadTicket, status_code=201, summary="Get a presigned URL to upload one file")
async def create_upload(body: UploadRequest, user: CurrentUser = Depends(current_user),
                        conn: asyncpg.Connection = Depends(get_conn)):
    kind = UPLOAD_KINDS[body.kind]
    if body.content_type not in kind.content_types:
        raise HTTPException(422, f"File type {body.content_type} isn't allowed. Allowed: "
                                 + ", ".join(kind.content_types))
    if body.size_bytes > kind.max_bytes:
        raise HTTPException(422, f"Files for {body.kind} can be at most {kind.max_bytes // MB} MB.")
    check_sha256_b64(body.checksum_sha256)
    if body.kind == "course_material":
        if body.course_id is None:
            raise HTTPException(422, "course_id is required for course materials.")
        # Anyone signed in shares materials (rev 22); the file is checked when it's attached.
        if not await conn.fetchval("SELECT EXISTS (SELECT 1 FROM courses WHERE id = $1)", body.course_id):
            raise HTTPException(404, "Course not found.")
    if body.kind == "job_description" and not await is_module_moderator(conn, user, "placement_hub"):
        raise forbidden("Only Placement Hub moderators can upload job descriptions.")
    if body.kind == "mess_menu" and not await is_module_moderator(conn, user, "events"):
        raise forbidden("Only Events moderators can upload mess menus.")
    key = new_object_key(body.kind, user.id, body.content_type, body.course_id)
    return UploadTicket(
        s3_key=key,
        upload_url=presign_put(key, body.content_type, body.size_bytes, body.checksum_sha256),
        headers={"Content-Type": body.content_type, "x-amz-checksum-sha256": body.checksum_sha256,
                 "x-amz-tagging": PENDING_TAG},
        expires_in=get_settings().upload_url_expiry_seconds,
    )
