# DevOps Practical Task – Step-by-Step Plan

Architecture: Internet → ALB (HTTPS/ACM) → Auto Scaling EC2 (private subnets) → RDS MySQL (private subnets)
Also: ALB → S3 (access logs). EC2 reads DB credentials from Secrets Manager.

## Directory Layout

```
aws-devops-task/
├── app/                        # Application source code (Python Flask)
│   ├── app.py                  # "/" page + "/health" endpoint (checks DB)
│   ├── requirements.txt
│   └── templates/
├── terraform/
│   ├── bootstrap/              # Run once: S3 state bucket, DynamoDB lock, GitHub OIDC role
│   ├── modules/
│   │   ├── vpc/                # VPC, 2 public + 2 private subnets, IGW, NAT, route tables
│   │   ├── security-groups/    # ALB SG, EC2 SG, RDS SG (chained, least privilege)
│   │   ├── iam/                # EC2 instance role + profile (Secrets read, S3 app bucket, SSM)
│   │   ├── s3/                 # App storage bucket + ALB logs bucket (encrypted, private)
│   │   ├── secrets/            # Secrets Manager secret for DB username/password
│   │   ├── rds/                # MySQL in private subnets, encrypted, Multi-AZ optional
│   │   ├── acm/                # ACM certificate + DNS validation (Route 53)
│   │   ├── alb/                # ALB, target group, HTTP→HTTPS redirect, HTTPS listener, logs
│   │   └── asg/                # Launch template (user_data), Auto Scaling Group
│   └── envs/
│       └── dev/                # main.tf wiring modules, variables, backend, outputs
├── .github/workflows/          # terraform.yml: fmt, validate, plan (PR), apply (main)
├── scripts/                    # user_data.sh (installs app on EC2), health-check script
└── docs/
    ├── architecture/           # Architecture diagram (PNG/draw.io)
    ├── screenshots/            # Console & pipeline screenshots
    └── DEPLOYMENT.md           # Deployment documentation
```

## Prerequisites (do these first)

1. AWS account + IAM admin user for initial setup; AWS CLI configured (`aws configure`).
2. Install Terraform (>= 1.6), Git, GitHub account.
3. **A domain name** – required for ACM HTTPS. Best: a Route 53 hosted zone
   (buy a cheap domain or use one you own and delegate NS records to Route 53).
4. Choose region (e.g. `ap-south-1`) – needs at least 2 AZs.

## Step-by-Step Execution

### Step 1 – Repository setup
- `git init`, create GitHub repo, add `.gitignore` (`.terraform/`, `*.tfstate*`, `*.tfvars` with secrets).

### Step 2 – Application (`app/`)
- Simple Flask app: `/` shows instance ID + AZ + DB connection status; `/health` returns 200.
- Reads DB credentials from Secrets Manager via boto3 (no hard-coded passwords).
- Runs with gunicorn on port 8080 as a systemd service.

### Step 3 – Bootstrap (`terraform/bootstrap/`)
- S3 bucket for Terraform remote state (versioning + encryption + block public access).
- State locking via S3 native lockfile (`use_lockfile = true`, Terraform >= 1.10), so no DynamoDB table is needed.
- GitHub OIDC provider + IAM role that GitHub Actions assumes (no long-lived keys).
- Apply locally once: `terraform init && terraform apply`.

### Step 4 – VPC module
- VPC `10.0.0.0/16`; public subnets in 2 AZs; private app subnets in 2 AZs; private DB subnets in 2 AZs.
- Internet Gateway; NAT Gateway in public subnet (1 for cost, or 1 per AZ for HA).
- Public route table → IGW; private route table → NAT.

### Step 5 – Security Groups module
- ALB SG: inbound 443 + 80 (redirect only) from `0.0.0.0/0`.
- EC2 SG: inbound 8080 **only from ALB SG**. No SSH (use SSM Session Manager).
- RDS SG: inbound 3306 **only from EC2 SG**.

### Step 6 – S3 module
- App bucket: SSE encryption, versioning, block public access.
- ALB logs bucket: bucket policy allowing ELB log delivery, lifecycle expiry.

### Step 7 – Secrets Manager module
- `random_password` → secret JSON `{username, password, host, dbname}`.
- (Alternative: RDS `manage_master_user_password = true`.)

### Step 8 – RDS module
- DB subnet group (private DB subnets), MySQL 8.0, `storage_encrypted = true`,
  `publicly_accessible = false`, backups enabled, `multi_az` variable.

### Step 9 – IAM module
- EC2 role: `secretsmanager:GetSecretValue` on **only** the DB secret ARN,
  S3 access on **only** the app bucket, `AmazonSSMManagedInstanceCore`.

### Step 10 – ACM module
- Certificate for `app.<yourdomain>`, DNS validation records in Route 53,
  `aws_acm_certificate_validation`.

### Step 11 – ALB module
- Internet-facing ALB in public subnets, access logs → S3 logs bucket.
- Listener 80 → redirect 443; listener 443 with ACM cert + modern TLS policy.
- Target group port 8080, health check path `/health`.
- Route 53 alias record `app.<yourdomain>` → ALB.

### Step 12 – ASG module
- Launch template: Amazon Linux 2023, instance profile, EC2 SG, IMDSv2 required,
  encrypted EBS, `user_data` (from `scripts/user_data.sh`) installs and starts the app.
- ASG in private app subnets, min 2 / desired 2 / max 4, ELB health checks,
  target-tracking scaling on CPU 60%.

### Step 13 – Environment wiring (`terraform/envs/dev/`)
- `backend.tf` (S3 + DynamoDB), `providers.tf`, `main.tf` calling all modules,
  `variables.tf`, `terraform.tfvars` (non-secret), `outputs.tf` (ALB DNS, app URL, RDS endpoint).
- Test locally: `terraform init`, `fmt`, `validate`, `plan`, `apply`.

### Step 14 – GitHub Actions (`.github/workflows/terraform.yml`)
- Trigger: PR → `fmt -check`, `validate`, `plan` (post plan as PR comment);
  push to `main` → `apply -auto-approve`.
- Auth via OIDC (`aws-actions/configure-aws-credentials` with role ARN).
- Optional: `tflint` / `checkov` security scan, manual `destroy` workflow.
- Post-apply job: `curl -f https://app.<yourdomain>/health`.

### Step 15 – Validation
- Open `https://app.<yourdomain>` → valid certificate, page loads.
- `http://` redirects to `https://`.
- Refresh shows different instance IDs (load balancing across AZs).
- Target group: all targets healthy. Terminate an instance → ASG replaces it.
- ALB logs appear in S3. RDS not publicly reachable.

### Step 16 – Documentation & Deliverables
- `docs/architecture/` – diagram (draw.io / diagrams.net).
- `docs/screenshots/` – VPC, subnets, ALB, target group, ASG, RDS, Secrets Manager,
  S3 logs, ACM cert, GitHub Actions run, browser with HTTPS.
- `docs/DEPLOYMENT.md` + root `README.md` – prerequisites, steps, how to destroy.
- Share: GitHub repo link + working HTTPS URL.

### Step 17 – Cost cleanup
- After submission/review: `terraform destroy` (NAT Gateway, ALB, RDS cost money hourly).

## Suggested 2-Day Timeline
- **Day 1:** Steps 1–9 (app, bootstrap, network, security, storage, DB).
- **Day 2:** Steps 10–17 (HTTPS, ALB, ASG, CI/CD, testing, docs, screenshots).
