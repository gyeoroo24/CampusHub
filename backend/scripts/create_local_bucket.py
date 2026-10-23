"""Create the uploads bucket in the docker-compose MinIO. Run once after `docker compose up -d`."""
import boto3

s3 = boto3.client("s3", endpoint_url="http://localhost:9000", region_name="ap-south-1",
                  aws_access_key_id="minioadmin", aws_secret_access_key="minioadmin")
existing = {b["Name"] for b in s3.list_buckets().get("Buckets", [])}
if "campushub-uploads" not in existing:
    s3.create_bucket(Bucket="campushub-uploads", CreateBucketConfiguration={"LocationConstraint": "ap-south-1"})
print("Bucket campushub-uploads is ready.")
