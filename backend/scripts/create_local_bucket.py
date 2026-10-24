"""Create the uploads bucket in the docker-compose MinIO if it's missing.

docker compose already creates it on start, so this is only needed if the bucket was deleted.
Uses the same MinIO login as the API (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY, default minioadmin).
"""
import os

import boto3

s3 = boto3.client("s3", endpoint_url="http://localhost:9000", region_name="ap-south-1",
                  aws_access_key_id=os.environ.get("AWS_ACCESS_KEY_ID", "minioadmin"),
                  aws_secret_access_key=os.environ.get("AWS_SECRET_ACCESS_KEY", "minioadmin"))
existing = {b["Name"] for b in s3.list_buckets().get("Buckets", [])}
if "campushub-uploads" not in existing:
    s3.create_bucket(Bucket="campushub-uploads", CreateBucketConfiguration={"LocationConstraint": "ap-south-1"})
print("Bucket campushub-uploads is ready.")
