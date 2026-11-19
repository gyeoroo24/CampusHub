# Restoring the CampusHub data snapshot

This guide puts a data snapshot into your own deployment of the `main` branch. It is the long form of
[readme step 5.7](../readme.md#57-load-the-database).

There are two snapshots:

- **The team's real snapshot.** The live database and the uploaded files (photos, mess menus), taken by
  `terraform/scripts/snapshot_export.sh`. It holds personal data (names, IISc emails, phone numbers,
  messages), so it is never committed and is shared only by a private channel. Do not paste it into
  chats, and delete your copy when you no longer need it. `terraform/data/snapshot/` is in `.gitignore`
  for this reason.
- **The mock snapshot**, committed at `terraform/data/mock-snapshot/`. Same schema, fully synthetic data
  labelled "Mock"/"Fictional", no admin. Use it if you don't have the real one.

Both are at schema revision 24 (the real one was taken on 3 November 2026).

## What a snapshot holds

```
campushub.dump   the database (pg_dump, custom format)
uploads/         the media bucket's files, with their original keys
MANIFEST.txt     when it was taken and row counts (the real one also names the code commit)
```

## Steps

**1. Deploy the stack.** Follow [readme section 5](../readme.md#5-deploy-to-aws) up to and including
5.6: create the state bucket (5.2), build the PostgreSQL layer (5.3, required: the data-tools function
won't deploy without it), and initialise with your own state bucket:

```bash
cd terraform
terraform init -backend-config="bucket=<state_bucket_name from 5.2>"
terraform apply
```

A plain `terraform init` fails with `403` because `versions.tf` names another account's bucket. After
the first apply, add the CloudFront address to `additional_callback_urls` and apply again (5.6).

**2. Put the snapshot in place.** From the repository root:

```bash
mkdir -p terraform/data/snapshot
cp -r terraform/data/mock-snapshot/* terraform/data/snapshot/     # or copy the real snapshot's files here
```

**3. Restore the database and uploads.** From `terraform/`:

```bash
./scripts/snapshot_restore.sh            # refuses if the database already has tables
FORCE=1 ./scripts/snapshot_restore.sh    # replaces existing tables (only on a fresh deployment)
```

The script uploads the dump to the media bucket, asks the data-tools function to restore it, prints the
row counts (compare them with `MANIFEST.txt`), and syncs `uploads/` to the bucket.

**4. Apply the newer migrations.** A revision 24 snapshot needs `025_company_created_by.sql` and
`026_unblock_requests_bookmarks.sql`, then the one-off cleanup `027_audit_cleanup.sql`. Run the loop in
[readme step 5.7](../readme.md#57-load-the-database), which sends each file to the data-tools function's
`migrate` action.

**5. Deactivate accounts with no Cognito user (optional).** Restored users have no account in this
deployment's Cognito pool. They can sign up again with the same email, and the backend links the new
sign-in to their existing record. To mark the others as deactivated instead (the admin is never touched):

```bash
./scripts/deactivate_missing_cognito_users.sh            # dry run: lists who would be deactivated
./scripts/deactivate_missing_cognito_users.sh --apply
```

**6. Publish the web app.** `./scripts/deploy_frontend.sh` (readme 5.8).

**7. Create the first admin.** Neither snapshot has an admin. Sign up in the app with an `iisc.ac.in`
address you can receive mail at, then promote that account with the data-tools command in
[readme 7.3](../readme.md#73-administrator-and-moderator-tasks).

**8. Clean up.** Delete `terraform/data/snapshot/` when you no longer need the local copy.

## Troubleshooting

- **`no snapshot at ...`:** the folder is missing or in the wrong place. Step 2.
- **`the database already has N tables`:** the database isn't empty. Use `FORCE=1` only on a fresh
  deployment.
- **`pg_dump failed` / `GLIBC` errors:** the data-tools layer was built on the wrong system. Rebuild it
  with `terraform/modules/data_tools/pg_layer/build.sh` (it builds inside Amazon Linux 2).
- **Photos show as broken after restore:** the uploads didn't sync, or the bucket name in
  `CAMPUSHUB_S3_BUCKET` doesn't match. Run step 3 again.
- **Mess menu can't be read:** the optional OCR layer isn't attached. Build it with
  `terraform/modules/compute/tesseract_layer/build.sh` (Docker, 30 to 60 minutes on an ARM Mac), set
  `tesseract_layer_zip = "modules/compute/tesseract_layer/tesseract-layer.zip"` and apply.
