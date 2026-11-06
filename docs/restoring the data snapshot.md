# Restoring the CampusHub data snapshot

This guide is for a teammate who has received a snapshot folder (`snapshot/`) by a private channel and
wants the same data in their own AWS account. The snapshot is the live database and the uploaded files
(photos, mess menus) from the reference deployment, taken by `terraform/scripts/snapshot_export.sh`.

**Privacy.** The snapshot holds personal data: names, IISc emails, phone numbers, and messages. Do not
commit it to git, do not paste it into chats, and delete your copy when you no longer need it.
`terraform/data/snapshot/` is in `.gitignore` for this reason.

## What you should have

```
snapshot/
  campushub.dump   the database (pg_dump, custom format)
  uploads/         the media bucket's files, with their original keys
  MANIFEST.txt     when it was taken, the code commit it was taken with, and row counts
```

Read `MANIFEST.txt` first. Its `code commit` line is the commit of this repository that the data
matches. Check out that commit before you deploy. Newer code may expect a different schema.

## Steps

**1. Get the code at the commit in the manifest.**

```bash
git checkout <commit from MANIFEST.txt>
```

**2. Put the snapshot in place.** The restore scripts look for it here:

```bash
mkdir -p terraform/data/snapshot
# copy campushub.dump, uploads/ and MANIFEST.txt into terraform/data/snapshot/
```

**3. Build the two Lambda layers that the data tools and the mess-menu reader use.** Both need Docker.
The first is required, because the data-tools function won't deploy without the PostgreSQL layer.

```bash
terraform/modules/data_tools/pg_layer/build.sh          # required, a few minutes
terraform/modules/compute/tesseract_layer/build.sh      # optional: mess-menu reading, 30-60 min on an ARM Mac
```

**4. Set up AWS and deploy.** Use `terraform/terraform.tfvars` for your account:

- `cognito_domain_prefix`: a name only you use, for example `campushub-<yourname>`.
- `tesseract_layer_zip = "modules/compute/tesseract_layer/tesseract-layer.zip"` if you built the OCR layer.

Then:

```bash
cd terraform
terraform init
terraform apply
```

The first apply creates the database, the Lambda functions, the data-tools function and the
frontend bucket.

**5. Add the CloudFront address to Cognito.** Read it with `terraform output cloudfront_domain_name`,
put `additional_callback_urls = ["https://<that domain>/"]` in `terraform.tfvars`, and apply again.

**6. Restore the database and uploads.**

```bash
./scripts/snapshot_restore.sh            # refuses if the database already has tables
FORCE=1 ./scripts/snapshot_restore.sh    # replaces existing tables (only when the first run refused and you are sure)
```

The script uploads the dump to the media bucket, asks the data-tools function to restore it, and syncs
`uploads/` to the bucket. It prints the restore result, and that should match `MANIFEST.txt`.

**7. Check the counts.** Run the export script's counts step or compare with `MANIFEST.txt`:

```bash
echo '{"action":"counts"}' > payload.json
aws lambda invoke --function-name $(terraform output -raw data_tools_function_name) \
  --payload fileb://payload.json counts.json && cat counts.json && rm payload.json
```

`users`, `listings`, `notifications` and the other tables should match the manifest.

**8. Deploy the web app.** Its API and Cognito settings are read from the Terraform outputs:

```bash
./scripts/deploy_frontend.sh
```

Open the printed CloudFront address and sign in with a seeded account (see the team's notes).

**9. Clean up.** Delete `terraform/data/snapshot/` when you no longer need the local copy.

## Troubleshooting

- **`no snapshot at ...`:** the folder is missing or in the wrong place. Step 2.
- **`the database already has N tables`:** the database isn't empty. Use `FORCE=1` only on a fresh deployment.
- **`pg_dump failed` / `GLIBC` errors:** the data-tools layer was built on the wrong system. Rebuild it
  with `pg_layer/build.sh` (it builds inside Amazon Linux 2).
- **Photos show as broken after restore:** the uploads didn't sync, or the bucket name in
  `CAMPUSHUB_S3_BUCKET` doesn't match. Run step 6 again.
- **Mess menu can't be read:** the OCR layer isn't attached. Build it (step 3) and set `tesseract_layer_zip`.
