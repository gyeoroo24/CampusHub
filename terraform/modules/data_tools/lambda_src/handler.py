"""Database snapshot tool for CampusHub, run inside the VPC by the data-tools Lambda.

Payloads (invoke with `aws lambda invoke --payload ...`):
  {"action": "export"}                                 pg_dump -> s3://<media bucket>/_snapshots/<name>.dump
  {"action": "restore", "key": "_snapshots/x.dump",    replaces the public schema with the dump; refuses
   "force": false}                                     if the database already has tables, unless force is true
  {"action": "counts"}                                 row counts of the main tables
  {"action": "run_sql", "key": "_snapshots/x.sql"}     runs a SQL file (a db/migrations upgrade) against the database

The PostgreSQL client programs (pg_dump, pg_restore, psql) come from the pg layer under /opt/bin.
Only boto3 and the standard library are used here.
"""
import json
import os
import subprocess
import time

import boto3

BUCKET = os.environ["MEDIA_BUCKET"]
SNAPSHOT_PREFIX = "_snapshots/"
LOCAL_DUMP = "/tmp/campushub.dump"
LOCAL_SQL = "/tmp/migration.sql"
MAIN_TABLES = ["users", "listings", "notifications", "comments", "threads", "placement_records",
               "course_feedback", "events", "mess_menus", "moderation_log"]

s3 = boto3.client("s3")


def _db_env():
    secret = json.loads(boto3.client("secretsmanager").get_secret_value(SecretId=os.environ["SECRET_ARN"])["SecretString"])
    env = dict(os.environ)
    env.update({
        "PATH": "/opt/bin:" + os.environ.get("PATH", ""),
        "LD_LIBRARY_PATH": "/opt/lib",
        "PGHOST": os.environ["DB_HOST"],
        "PGPORT": str(secret.get("port", 5432)),
        "PGUSER": secret["username"],
        "PGPASSWORD": secret["password"],
        "PGDATABASE": os.environ["DB_NAME"],
        "PGSSLMODE": "require",
    })
    return env


def _run(args, env):
    result = subprocess.run(args, env=env, capture_output=True, text=True, timeout=800)
    if result.returncode != 0:
        raise RuntimeError(f"{args[0]} failed: {result.stderr[-2000:]}")
    return result.stdout


def export(event):
    env = _db_env()
    key = event.get("key") or f"{SNAPSHOT_PREFIX}campushub-{time.strftime('%Y%m%d-%H%M%S', time.gmtime())}.dump"
    _run(["pg_dump", "-Fc", "--no-owner", "--no-acl", "-f", LOCAL_DUMP], env)
    s3.upload_file(LOCAL_DUMP, BUCKET, key)
    return {"key": key, "bytes": os.path.getsize(LOCAL_DUMP)}


def restore(event):
    key = event["key"]
    env = _db_env()
    existing = int(_run(["psql", "-tAc", "select count(*) from information_schema.tables where table_schema = 'public'"], env).strip())
    if existing and not event.get("force"):
        return {"refused": f"the database already has {existing} tables; send force=true to replace them"}
    s3.download_file(BUCKET, key, LOCAL_DUMP)
    _run(["psql", "-v", "ON_ERROR_STOP=1", "-c", "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"], env)
    _run(["pg_restore", "--no-owner", "--no-acl", "-d", env["PGDATABASE"], LOCAL_DUMP], env)
    os.remove(LOCAL_DUMP)
    return counts({})


def run_sql(event):
    key = event["key"]
    if not key.startswith(SNAPSHOT_PREFIX):
        raise ValueError("run_sql only reads files under _snapshots/")
    env = _db_env()
    s3.download_file(BUCKET, key, LOCAL_SQL)
    _run(["psql", "-v", "ON_ERROR_STOP=1", "-f", LOCAL_SQL], env)
    os.remove(LOCAL_SQL)
    return {"ran": key}


def counts(_event):
    env = _db_env()
    result = {}
    for table in MAIN_TABLES:
        try:
            result[table] = int(_run(["psql", "-tAc", f"select count(*) from {table}"], env).strip())
        except RuntimeError:
            result[table] = None   # table not in this schema revision
    return result


def handler(event, _context):
    action = event.get("action")
    if action == "export":
        return export(event)
    if action == "restore":
        return restore(event)
    if action == "counts":
        return counts(event)
    if action == "run_sql":
        return run_sql(event)
    raise ValueError(f"unknown action {action!r}")
