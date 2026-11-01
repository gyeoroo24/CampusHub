"""S3 uploads and downloads.

Upload flow (keeps big files off Lambda):
  1. Client asks POST /uploads for a ticket: kind, content type, size, SHA-256 (base64).
  2. API returns a presigned PUT URL. Content-Type, Content-Length and x-amz-checksum-sha256
     are part of the signature, so S3 rejects a different file type, a different size or a
     corrupted upload (NFR-8). The file is also tagged state=pending.
  3. Client PUTs the file straight to S3 with exactly those headers.
  4. Client creates/updates the post with the returned s3_key. The API checks the key is
     inside the caller's own folder and that the object really exists with an allowed
     size and type before saving it, then retags it state=attached. A file that fails the
     check is deleted. Files never attached keep state=pending, and an S3 lifecycle rule on
     that tag (see README) deletes them after a day.

The database stores only object keys. Files are served through short-lived links: signed
CloudFront URLs when cdn_base_url is set, otherwise presigned S3 GET URLs.
"""
import asyncio
import base64
import binascii
import logging
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from functools import lru_cache
from urllib.parse import quote
from uuid import UUID

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError
from botocore.signers import CloudFrontSigner
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from fastapi import HTTPException

from .config import get_settings

log = logging.getLogger("campushub.storage")

MB = 1024 * 1024
IMAGE_TYPES = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "image/heic": "heic"}
MATERIAL_TYPES = {
    **IMAGE_TYPES,
    "application/pdf": "pdf",
    "application/vnd.openxmlformats-officedocument.presentationml.presentation": "pptx",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "docx",
    "application/zip": "zip",
    "text/plain": "txt",
}

DOCUMENT_TYPES = {
    "application/pdf": "pdf",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "docx",
    "text/plain": "txt",
}


@dataclass(frozen=True)
class UploadKind:
    folder: str
    content_types: dict[str, str]
    max_bytes: int


UPLOAD_KINDS: dict[str, UploadKind] = {
    "listing_photo": UploadKind("listings", IMAGE_TYPES, 10 * MB),
    "lost_report_photo": UploadKind("lost-reports", IMAGE_TYPES, 10 * MB),
    "found_report_photo": UploadKind("found-reports", IMAGE_TYPES, 10 * MB),
    "course_material": UploadKind("course-materials", MATERIAL_TYPES, 50 * MB),
    # Placement Hub: a JD file attached to a company's role (placement moderators only).
    "job_description": UploadKind("job-descriptions", DOCUMENT_TYPES, 20 * MB),
}


@lru_cache
def s3_client():
    s = get_settings()
    return boto3.client(
        "s3",
        region_name=s.s3_region,
        endpoint_url=s.s3_endpoint_url,
        # Only add checksums we ask for, so presigned URLs carry exactly the headers we sign.
        config=Config(signature_version="s3v4",
                      request_checksum_calculation="when_required",
                      response_checksum_validation="when_required"),
    )


def owner_folder(kind: str, user_id: UUID, course_id: UUID | None = None) -> str:
    """Every user uploads into their own folder, so nobody can attach someone else's file."""
    folder = UPLOAD_KINDS[kind].folder
    if kind == "course_material":
        return f"{folder}/{course_id}/{user_id}/"
    return f"{folder}/{user_id}/"


def new_object_key(kind: str, user_id: UUID, content_type: str, course_id: UUID | None = None) -> str:
    ext = UPLOAD_KINDS[kind].content_types[content_type]
    return f"{owner_folder(kind, user_id, course_id)}{uuid.uuid4()}.{ext}"


def check_sha256_b64(value: str) -> None:
    try:
        raw = base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise HTTPException(422, "checksum_sha256 must be the base64-encoded SHA-256 of the file.") from exc
    if len(raw) != 32:
        raise HTTPException(422, "checksum_sha256 must be the base64-encoded SHA-256 of the file.")


PENDING_TAG = "state=pending"


def presign_put(key: str, content_type: str, size_bytes: int, checksum_sha256_b64: str) -> str:
    s = get_settings()
    return s3_client().generate_presigned_url(
        "put_object",
        Params={"Bucket": s.s3_bucket, "Key": key, "ContentType": content_type, "ContentLength": size_bytes,
                "ChecksumSHA256": checksum_sha256_b64, "Tagging": PENDING_TAG},
        ExpiresIn=s.upload_url_expiry_seconds,
    )


@lru_cache
def _cdn_signer() -> CloudFrontSigner:
    s = get_settings()
    key = serialization.load_pem_private_key(s.cdn_private_key.encode(), password=None)
    # CloudFront signed URLs use RSA with SHA-1.
    return CloudFrontSigner(s.cdn_key_pair_id, lambda message: key.sign(message, padding.PKCS1v15(), hashes.SHA1()))


def file_url(key: str) -> str:
    """A link to the file that expires after download_url_expiry_seconds."""
    s = get_settings()
    if s.cdn_base_url:
        expires = datetime.now(timezone.utc) + timedelta(seconds=s.download_url_expiry_seconds)
        return _cdn_signer().generate_presigned_url(f"{s.cdn_base_url.rstrip('/')}/{quote(key)}",
                                                    date_less_than=expires)
    return s3_client().generate_presigned_url(
        "get_object", Params={"Bucket": s.s3_bucket, "Key": key}, ExpiresIn=s.download_url_expiry_seconds)


async def _verify_object(key: str, kind: UploadKind) -> None:
    s = get_settings()
    try:
        head = await asyncio.to_thread(s3_client().head_object, Bucket=s.s3_bucket, Key=key)
    except ClientError as exc:
        # Without s3:ListBucket, S3 answers 403 rather than 404 for a missing object.
        if exc.response.get("Error", {}).get("Code") in ("404", "NoSuchKey", "NotFound", "403", "AccessDenied"):
            raise HTTPException(422, f"File {key} has not been uploaded yet. Finish the upload first.") from exc
        raise
    problem = None
    if head["ContentLength"] > kind.max_bytes:
        problem = f"File {key} is larger than {kind.max_bytes // MB} MB."
    elif head.get("ContentType") not in kind.content_types:
        problem = f"File {key} has a file type that isn't allowed here."
    if problem:
        await delete_objects([key])
        raise HTTPException(422, problem)


async def verify_own_uploads(keys: list[str], kind: str, user_id: UUID, course_id: UUID | None = None) -> None:
    """Every key must be in the caller's folder for this kind, and exist in S3 with an allowed size/type."""
    folder = owner_folder(kind, user_id, course_id)
    for key in keys:
        if not key.startswith(folder):
            raise HTTPException(422, f"File {key} wasn't uploaded by you for this purpose. "
                                     "Request a new upload with POST /uploads.")
    await asyncio.gather(*(_verify_object(k, UPLOAD_KINDS[kind]) for k in keys))


async def mark_attached(keys: list[str]) -> None:
    """Best effort, after the post is saved: retag the files so the lifecycle rule keeps them."""
    s = get_settings()

    def tag(key: str) -> None:
        s3_client().put_object_tagging(Bucket=s.s3_bucket, Key=key,
                                       Tagging={"TagSet": [{"Key": "state", "Value": "attached"}]})
    for key in keys:
        try:
            await asyncio.to_thread(tag, key)
        except Exception:  # noqa: BLE001 - the post is already saved; never fail the request here
            log.exception("Could not mark %s as attached; the lifecycle rule may delete it", key)


async def put_object(key: str, body: bytes, content_type: str) -> None:
    """Store a file the API itself produced (e.g. a pasted placement sheet, kept as the import's source)."""
    s = get_settings()
    await asyncio.to_thread(s3_client().put_object, Bucket=s.s3_bucket, Key=key, Body=body,
                            ContentType=content_type, Tagging="state=attached")


async def delete_objects(keys: list[str]) -> None:
    """Best effort: called after a post or its photos are deleted. Failures are logged, not raised."""
    if not keys:
        return
    s = get_settings()
    for start in range(0, len(keys), 1000):
        batch = [{"Key": k} for k in keys[start:start + 1000]]
        try:
            resp = await asyncio.to_thread(s3_client().delete_objects, Bucket=s.s3_bucket, Delete={"Objects": batch})
        except Exception:  # noqa: BLE001 - cleanup must never break the request
            log.exception("Could not delete %d S3 objects", len(batch))
            continue
        for err in resp.get("Errors", []):
            log.error("Could not delete S3 object %s: %s %s", err.get("Key"), err.get("Code"), err.get("Message"))
