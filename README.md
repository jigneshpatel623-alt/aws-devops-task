# AWS DevOps Practical Task – Infrastructure & CI/CD

A highly available web application on AWS, provisioned entirely with **Terraform** and deployed through **GitHub Actions**.

```
Internet → Route 53 → ALB (HTTPS, ACM) → Auto Scaling EC2 (private, 2 AZs) → RDS MySQL (private)
                        └→ S3 (access logs)
```

## What's included

| Area | Implementation |
|---|---|
| Networking | VPC, public/private-app/private-db subnets in 2 AZs, IGW, NAT Gateway, route tables |
| Compute | Launch Template (AL2023, IMDSv2, encrypted EBS) + Auto Scaling Group with CPU target tracking and rolling instance refresh |
| Load balancing | ALB, HTTPS listener (TLS 1.3 policy), HTTP→HTTPS redirect, `/health` checks, access logs to S3 |
| Database | RDS MySQL 8.0 in private subnets, encrypted, TLS required, automated backups |
| Secrets | Generated DB password stored in Secrets Manager and read by the app at runtime |
| IAM | EC2 role limited to one secret and one bucket, plus SSM; GitHub OIDC deploy role (no access keys) |
| Storage | App bucket (versioned) and ALB logs bucket (lifecycle); both encrypted, private, TLS-only |
| CI/CD | fmt, validate, Checkov, plan on PR (as a comment), apply on `main`, health checks, manual destroy |

## Repository layout

```
app/                    Flask application (Python)
scripts/                EC2 user_data, health check script
terraform/bootstrap/    State bucket + GitHub OIDC role (run once)
terraform/modules/      vpc, security-groups, s3, secrets, rds, iam, acm, alb, asg
terraform/envs/dev/     Environment that connects all the modules
.github/workflows/      terraform.yml (CI/CD), destroy.yml
docs/                   Architecture diagram, deployment guide, screenshots
```

## Quick start

See **[docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)** for full steps.

1. `terraform/bootstrap`: `terraform apply`
2. Add GitHub secret `AWS_ROLE_ARN` and variables `AWS_REGION`, `TF_STATE_BUCKET`, `DOMAIN_NAME`, `APP_SUBDOMAIN`
3. Push to `main`. The pipeline deploys the stack and runs health checks.

## Architecture

See [docs/architecture/architecture.md](docs/architecture/architecture.md).

## Application endpoints

| Path | Purpose |
|---|---|
| `/` | Instance ID, AZ, DB status and a visit counter stored in RDS |
| `/health` | Liveness check used by the ALB |
| `/db-health` | Database connectivity check |
