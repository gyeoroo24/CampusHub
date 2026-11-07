"""Test setup: a real PostgreSQL database (schema loaded from db/schema.sql) and a mocked S3.

Needs a Postgres the tests can own, e.g. from docker-compose:
    docker compose up -d db
    CAMPUSHUB_TEST_DATABASE_URL=postgresql://campushub:campushub@localhost:5432/campushub_test pytest
The schema is dropped and reloaded once per test run, and every table is emptied before each test.
"""
import asyncio
import base64
import hashlib
import os
import pathlib

import asyncpg
import boto3
import pytest
from fastapi.testclient import TestClient
from moto import mock_aws

DB_URL = os.environ.get("CAMPUSHUB_TEST_DATABASE_URL",
                        "postgresql://campushub:campushub@localhost:5432/campushub_test")
BUCKET = "campushub-test"
os.environ.update({
    "CAMPUSHUB_DATABASE_URL": DB_URL,
    "CAMPUSHUB_AUTH_MODE": "dev",
    "CAMPUSHUB_ALLOW_DEV_AUTH": "true",
    "CAMPUSHUB_S3_BUCKET": BUCKET,
    "CAMPUSHUB_MATCH_MODE": "off",
    "CAMPUSHUB_MEAL_ALERTS_ON_REQUESTS": "false",
    "CAMPUSHUB_SENTIMENT_BACKEND": "lexicon",   # test_sentiment_backends.py covers the model and Comprehend
    "CAMPUSHUB_AUTO_FLAG": "false",  # test_auto_flagging.py turns it on   # tests that need the matcher switch it on with a fake embedder
    "CAMPUSHUB_S3_REGION": "ap-south-1",
    "AWS_ACCESS_KEY_ID": "testing",
    "AWS_SECRET_ACCESS_KEY": "testing",
    "AWS_DEFAULT_REGION": "ap-south-1",
})
# Ignore a local .env (e.g. its MinIO endpoint), so S3 calls go to the moto mock below.
from app.config import Settings  # noqa: E402
Settings.model_config["env_file"] = None
SCHEMA = pathlib.Path(__file__).resolve().parents[1] / "db" / "schema.sql"
API = "/api/v1"


def sql(query: str, *args):
    """Run SQL directly against the test database (setup and assertions)."""
    async def go():
        conn = await asyncpg.connect(DB_URL)
        try:
            return await conn.fetch(query, *args)
        finally:
            await conn.close()
    return asyncio.run(go())


@pytest.fixture(scope="session", autouse=True)
def database():
    async def go():
        conn = await asyncpg.connect(DB_URL)
        try:
            await conn.execute("DROP SCHEMA public CASCADE; CREATE SCHEMA public;")
            await conn.execute(SCHEMA.read_text())
        finally:
            await conn.close()
    asyncio.run(go())


@pytest.fixture(autouse=True)
def empty_tables(database):
    tables = [r["tablename"] for r in sql("SELECT tablename FROM pg_tables WHERE schemaname = 'public'")]
    sql(f"TRUNCATE {', '.join(tables)} RESTART IDENTITY CASCADE")


@pytest.fixture(scope="session")
def s3():
    with mock_aws():
        client = boto3.client("s3", region_name="ap-south-1")
        client.create_bucket(Bucket=BUCKET, CreateBucketConfiguration={"LocationConstraint": "ap-south-1"})
        yield client


@pytest.fixture(scope="session")
def client(s3):
    from app.config import get_settings
    from app.storage import s3_client
    get_settings.cache_clear()
    s3_client.cache_clear()
    from app.main import app
    with TestClient(app) as c:
        yield c


def as_user(email: str, name: str | None = None) -> dict:
    """Dev-mode auth header for a user (created on their first request)."""
    headers = {"X-Dev-User": email}
    if name:
        headers["X-Dev-Name"] = name
    return headers


ASHA = as_user("asha@iisc.ac.in", "Asha")
RAVI = as_user("ravi@iisc.ac.in", "Ravi")
MEERA = as_user("meera@iisc.ac.in", "Meera")
KIRAN = as_user("kiran@iisc.ac.in", "Kiran")
ADMIN = as_user("admin@iisc.ac.in", "Admin")


def sign_in(client, headers) -> str:
    """Make sure the user exists; returns their id."""
    r = client.get(f"{API}/me", headers=headers)
    assert r.status_code == 200, r.text
    return r.json()["id"]


def make_admin(client, headers) -> str:
    user_id = sign_in(client, headers)
    sql("UPDATE users SET base_role = 'admin' WHERE id = $1::uuid", user_id)
    return user_id


def grant(client, by, email, module, scope_type="module", department_id=None, course_id=None):
    return client.post(f"{API}/moderators", headers=by, json={
        "email": email, "module": module, "scope_type": scope_type,
        "department_id": department_id, "course_id": course_id})


# The API checks a file's first bytes match its type, so fake test images start with a real signature.
IMAGE_HEADERS = {"image/jpeg": b"\xff\xd8\xff\xe0", "image/png": b"\x89PNG\r\n\x1a\n"}


def image_bytes(content: bytes) -> bytes:
    """The test's fake image content without the signature upload() put in front of it."""
    for header in IMAGE_HEADERS.values():
        if content.startswith(header):
            return content[len(header):]
    return content


def upload(client, s3, headers, kind, content=b"fake image bytes", content_type="image/jpeg", course_id=None) -> str:
    """Get an upload ticket, then put the file in (mocked) S3 the way the app would."""
    header = IMAGE_HEADERS.get(content_type, b"")
    if not content.startswith(header):
        content = header + content
    checksum = base64.b64encode(hashlib.sha256(content).digest()).decode()
    r = client.post(f"{API}/uploads", headers=headers, json={
        "kind": kind, "content_type": content_type, "size_bytes": len(content),
        "checksum_sha256": checksum, "course_id": course_id})
    assert r.status_code == 201, r.text
    key = r.json()["s3_key"]
    s3.put_object(Bucket=BUCKET, Key=key, Body=content, ContentType=content_type, Tagging="state=pending")
    return key


def category(client, headers, path, name) -> int:
    r = client.post(f"{API}/{path}/categories", headers=headers, json={"name": name})
    assert r.status_code in (200, 201), r.text
    return r.json()["id"]


def post_event(client, headers, body):
    """Create an event as `headers`' user. Only Events moderators may (rev 21), so the user holds the role
    just for this call: they end up the event's organizer without staying a moderator, which keeps
    organizer-versus-others checks meaningful."""
    user_id = sign_in(client, headers)
    is_moderator = sql("""SELECT EXISTS (SELECT 1 FROM moderator_assignments WHERE user_id = $1::uuid
                          AND module = 'events' AND revoked_at IS NULL)""", user_id)[0][0]
    if is_moderator or sql("SELECT base_role = 'admin' FROM users WHERE id = $1::uuid", user_id)[0][0]:
        return client.post(f"{API}/events", headers=headers, json=body)
    grant_id = sql("""INSERT INTO moderator_assignments (user_id, module, scope_type, granted_by)
                      VALUES ($1::uuid, 'events', 'module', $1::uuid) RETURNING id""", user_id)[0][0]
    try:
        return client.post(f"{API}/events", headers=headers, json=body)
    finally:
        sql("UPDATE moderator_assignments SET revoked_at = now(), revoked_by = user_id WHERE id = $1", grant_id)
