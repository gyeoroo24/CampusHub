import base64
import hashlib
import urllib.parse

import pytest

from .conftest import API, ASHA

CHECKSUM = base64.b64encode(hashlib.sha256(b"photo").digest()).decode()


def _ticket(client, **overrides):
    body = {"kind": "listing_photo", "content_type": "image/jpeg", "size_bytes": 1000,
            "checksum_sha256": CHECKSUM} | overrides
    return client.post(f"{API}/uploads", headers=ASHA, json=body)


def test_ticket_signs_type_size_and_checksum(client):
    """NFR-8: S3 rejects an upload whose type, size or SHA-256 differs from what was signed."""
    r = _ticket(client)
    assert r.status_code == 201
    ticket = r.json()
    signed = urllib.parse.parse_qs(urllib.parse.urlparse(ticket["upload_url"]).query)["X-Amz-SignedHeaders"][0]
    assert set(signed.split(";")) >= {"content-type", "content-length", "x-amz-checksum-sha256", "x-amz-tagging"}
    assert ticket["headers"] == {"Content-Type": "image/jpeg", "x-amz-checksum-sha256": CHECKSUM,
                                 "x-amz-tagging": "state=pending"}
    assert ticket["s3_key"].startswith("listings/") and ticket["s3_key"].endswith(".jpg")


@pytest.mark.parametrize("overrides", [
    {"content_type": "application/x-msdownload"},          # not an image
    {"size_bytes": 11 * 1024 * 1024},                      # over 10 MB
    {"checksum_sha256": "not-base64!"},                    # bad checksum
    {"checksum_sha256": base64.b64encode(b"short").decode()},
    {"kind": "course_material", "content_type": "application/pdf"},  # missing course_id
])
def test_bad_upload_requests_rejected(client, overrides):
    assert _ticket(client, **overrides).status_code == 422


def test_guests_cannot_upload(client):
    r = client.post(f"{API}/uploads", json={"kind": "listing_photo", "content_type": "image/jpeg",
                                            "size_bytes": 10, "checksum_sha256": CHECKSUM})
    assert r.status_code == 401
