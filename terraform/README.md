# CampusHub Infrastructure as Code (Terraform)

**Course:** DS252 Introduction to Cloud Computing  
**Project:** CampusHub: An IISc Student Community Platform  
**Team:** Order of Phoenix  
**Target Region:** `ap-south-1` (Mumbai)

---

## 1. Architecture Overview & Component Mapping

This repository contains production-ready, modular Terraform code automating the serverless infrastructure proposed in `Proposal-Serverless-Architecture.jpg` and `Cloud_Computing_Project-PRD.pdf`.

```
                    +------------------------------------+
                    |        AWS Route 53 (DNS)          |
                    +-----------------+------------------+
                                      |
                                      v
                    +------------------------------------+
                    |       AWS WAF (Optional/Prod)      |
                    +-----------------+------------------+
                                      |
                                      v
             +--------------------------------------------------+
             |         AWS CloudFront Distribution (CDN)        |
             +------------------------+-------------------------+
                                      |
             +------------------------+-------------------------+
             | /* (Default)                                     | /api/* (API Traffic)
             v                                                  v
+-----------------------------+               +-----------------------------------+
|      S3 Frontend Bucket     |               |    AWS API Gateway (HTTP API v2)  |
|  (Flutter Web Static Build) |               | (no gateway-level authorizer; the |
|   Protected by OAC          |               |  FastAPI app checks auth itself)  |
+-----------------------------+               +-----------------+-----------------+
                                                                 |
                                                                 v
                                              +-----------------------------------+
                                              |       AWS Cognito User Pool       |
                                              | (Guests, Signed-in, Mods, Admins) |
                                              |  the app validates the ID token   |
                                              |   against this pool's JWKS        |
                                              +-----------------------------------+
                                                                 |
        +-------------------------------------------------------+
        | Private VPC Invocations
        v
+---------------------------------------------------------------------------------+
| VPC: 10.0.0.0/16 (Private Subnets across ap-south-1a, ap-south-1b, ap-south-1c) |
|                                                                                 |
|   +-------------------+  +--------------------+  +--------------------------+   |
|   |   Buy & Sell      |  |   Placement Hub    |  |  Academic Help Lambda    |   |
|   |   Lost & Found    |  |   Lambda Function  |  |  Community Events Lambda |   |
|   |   Lambdas (1a)    |  |   (1b)             |  |  (1c)                    |   |
|   +---------+---------+  +---------+----------+  +------------+-------------+   |
|             |                      |                          |                 |
|             +----------------------+--------------------------+                 |
|                                    |                                            |
|                                    v (VPC S3 Gateway Endpoint - 100% Free)      |
|                       +--------------------------+                              |
|                       |  S3 Media/Docs Storage   |                              |
|                       |  (Presigned Direct URL)  |                              |
|                       +--------------------------+                              |
|                                    |                                            |
|                                    v (Port 5432 - Direct Private SG Ingress)   |
|                       +--------------------------+                              |
|                       |   Amazon RDS PostgreSQL  |                              |
|                       |   (Single-AZ Free Tier   |                              |
|                       |   or Multi-AZ HA Flag)   |                              |
|                       +--------------------------+                              |
+---------------------------------------------------------------------------------+
```

---

## 2. Directory & Module Structure

```
terraform/
├── main.tf                    # Root composition connecting all modular tiers
├── variables.tf               # Global variables and cost guardrail flags
├── outputs.tf                 # Key endpoints (CloudFront URL, API Gateway, Cognito, DB)
├── providers.tf               # AWS provider configuration (ap-south-1 & us-east-1 alias)
├── versions.tf                # Terraform (>= 1.5.0), AWS provider, & remote backend template
├── terraform.tfvars.example   # Example configuration parameters
│
├── bootstrap/                 # One-time setup: Provisions S3 State Bucket & DynamoDB Lock Table
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
│
├── tests/                     # Automated testing scripts
│   ├── smoke_test.py          # Post-deployment end-to-end smoke test
│   └── test_permission_matrix.py # PRD Experiment 3 permission matrix validation
│
└── modules/
    ├── networking/            # VPC (10.0.0.0/16), 3 AZ subnets, S3 VPC Gateway Endpoint, App/DB SGs
    ├── database/              # RDS PostgreSQL, subnet group, parameter group (TLS 1.2+), SSM credentials
    ├── storage/               # S3 frontend static bucket + S3 user media upload bucket, versioning, CORS
    ├── auth/                  # Cognito User Pool, Client, and 4-role user groups (Guest/User/Mod/Admin)
    ├── compute/               # 5 Lambda functions (all built from backend/app, zip-packaged by
    │                          # build_lambda_zip.sh at apply time) in VPC, IAM least-privilege policies
    ├── api_gateway/           # HTTP API (v2); per-prefix routes to the 5 Lambdas, plus a catch-all;
    │                          # auth is enforced by the app itself, not a gateway-level authorizer
    ├── cdn/                   # CloudFront CDN with S3 OAC, API Gateway reverse proxy origin, SPA rewrites
    ├── waf/                   # Optional AWS WAFv2 WebACL with OWASP rules and IP rate limiting
    └── monitoring/            # AWS Budgets $5 free-tier limit, SNS alerts, CloudWatch metric alarms
```

---

## 3. Free Tier Feasibility Analysis & Design Choices

| Proposed Resource in PRD / Diagram | AWS Free Tier Status | Adopted Solution in Terraform |
| :--- | :--- | :--- |
| **RDS Multi-AZ Cluster (3 nodes)** | **NOT Free Tier** (Would incur immediate charges for 2 standby nodes) | `db.t4g.micro`, 20 GB gp3 storage. The `multi_az_db` variable currently **defaults to `true`** (not Free Tier — this incurs real standby-node cost); set `multi_az_db = false` in `terraform.tfvars` for a Free Tier single-AZ instance, or keep `true` deliberately for HA/benchmark testing. |
| **AWS WAF** | **NOT Free Tier** ($5/mo WebACL + $1/mo per rule) | Made **toggleable** (`enable_waf = false` by default). API Gateway's built-in throttling (50 req/s, 100 burst) handles edge rate-limiting for **$0**. |
| **VPC NAT Gateway** | **NOT Free Tier** (~$32.40/month per gateway) | Lambdas utilize the **free VPC Gateway Endpoint for S3**. API Gateway validates Cognito JWT at the edge, removing any need for Lambdas to make public internet calls. |
| **Route 53 Hosted Zone** | **NOT Free Tier** ($0.50/mo per zone + domain purchase) | CloudFront provides a free SSL certificate on `*.cloudfront.net`. Route 53 is decoupled and optional. |
| **Secrets Manager** | **NOT Free Tier** ($0.40/mo per secret) | Database credentials stored in **AWS SSM Parameter Store** (Standard parameters are **100% Free**). |
| **Compute & API Tier** | **100% Free Tier Eligible** | Lambda (1M free calls/mo + 400,000 GB-s) and API Gateway HTTP API (1M free calls/mo). |
| **CloudFront CDN** | **100% Free Tier Eligible** | Always Free Tier covers 1 TB Data Transfer Out and 10,000,000 requests per month. |
| **AWS Cognito** | **100% Free Tier Eligible** | Up to 50,000 Monthly Active Users (MAUs) are Always Free (more than enough for 6,000 IISc students). |

---

## 4. Team Remote State Backend Setup (Bootstrap)

Because **Order of Phoenix** is a 4-person team, storing Terraform state remotely in an S3 bucket with DynamoDB state locking is essential to prevent state corruption, race conditions, and accidental credential leaks.

### Step 1: Create the Backend Resources (Run once by one team member)
```bash
cd terraform/bootstrap
terraform init
terraform plan
terraform apply
```
This provisions:
- An encrypted S3 bucket (`campushub-tfstate-xxxx`) with versioning enabled.
- A DynamoDB table (`campushub-tf-locks`) with free `PAY_PER_REQUEST` billing.

### Step 2: Enable the Backend in Root Terraform
Open `terraform/versions.tf`, uncomment the `backend "s3"` block, and insert your bucket name:
```hcl
backend "s3" {
  bucket         = "campushub-tfstate-<YOUR_UNIQUE_ID>"
  key            = "campushub/dev/terraform.tfstate"
  region         = "ap-south-1"
  dynamodb_table = "campushub-tf-locks"
  encrypt        = true
}
```

Then initialize the root workspace:
```bash
cd ..
terraform init -migrate-state
terraform plan
terraform apply
```

---

## 5. Post-Deployment Testing & Verification Guide

Once you run `terraform apply`, test the functionality in order:

### 1. Automated Smoke Test (1 Command)
Run the automated test script against your CloudFront distribution URL:
```bash
python tests/smoke_test.py https://<YOUR_CLOUDFRONT_DOMAIN_NAME>
```
This tests:
- Public GET routes across all 5 microservices (`buy-sell`, `lost-found`, `placement`, `academic`, `events`).
- Unauthenticated POST rejection (`401 Unauthorized` enforcement by API Gateway).


### 2. Cognito User Flow & Authenticated Testing
1. Create a test IISc student user:
   ```bash
   aws cognito-idp sign-up \
     --client-id <cognito_client_id> \
     --username teststudent@iisc.ac.in \
     --password "CampusHubPass#2026"
   ```
2. Confirm user account (admin bypass):
   ```bash
   aws cognito-idp admin-confirm-sign-up \
     --user-pool-id <cognito_user_pool_id> \
     --username teststudent@iisc.ac.in
   ```
3. Assign to the `Signed-in` group:
   ```bash
   aws cognito-idp admin-add-user-to-group \
     --user-pool-id <cognito_user_pool_id> \
     --username teststudent@iisc.ac.in \
     --group-name "Signed-in"
   ```
3b. **Mark the email verified** — `admin-confirm-sign-up` alone does not set this, and the backend
    refuses to create the account (403) without it:
   ```bash
   aws cognito-idp admin-update-user-attributes \
     --user-pool-id <cognito_user_pool_id> \
     --username teststudent@iisc.ac.in \
     --user-attributes Name=email_verified,Value=true
   ```
4. Authenticate and retrieve the Cognito JWT IdToken:
   ```bash
   aws cognito-idp initiate-auth \
     --client-id <cognito_client_id> \
     --auth-flow USER_PASSWORD_AUTH \
     --auth-parameters USERNAME=teststudent@iisc.ac.in,PASSWORD="CampusHubPass#2026"
   ```
5. Test an authenticated POST request with the token:
   ```bash
   curl -i -X POST "https://<YOUR_CLOUDFRONT_DOMAIN_NAME>/api/buy-sell/items" \
     -H "Authorization: Bearer <ID_TOKEN>" \
     -H "Content-Type: application/json" \
     -d '{"title": "Bicycle", "price": 2500}'
   ```
   **Expected Response:** `200 OK` (processed by `buy_and_sell` Lambda).

