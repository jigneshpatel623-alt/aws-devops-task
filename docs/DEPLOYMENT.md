# Deployment Guide

## 0. Prerequisites

| Tool | Install (Windows) |
|---|---|
| Git | `winget install Git.Git` |
| Terraform ≥ 1.10 | `winget install Hashicorp.Terraform` |
| AWS CLI v2 | `winget install Amazon.AWSCLI` |
| GitHub CLI (optional) | `winget install GitHub.cli` |

You also need:
- An AWS account and an IAM user/role with admin rights, used only for the one-time bootstrap. Configure it with `aws configure`.
- A domain with a **Route 53 public hosted zone** (e.g. `example.com`). ACM uses it for DNS validation.
- A GitHub repository: `jigneshpatel623-alt/aws-devops-task`.

## 1. Bootstrap (one time, local)

```powershell
cd terraform/bootstrap
terraform init
terraform apply
terraform output
```

Write down the two outputs:
- `state_bucket`: the S3 bucket for Terraform remote state
- `github_actions_role_arn`: the IAM role GitHub Actions assumes through OIDC

> Keep `terraform/bootstrap/terraform.tfstate` safe (it is git-ignored). It is the only state file for the bootstrap resources.

## 2. Configure GitHub

Repository → **Settings → Secrets and variables → Actions**

| Type | Name | Value |
|---|---|---|
| Secret | `AWS_ROLE_ARN` | `github_actions_role_arn` output |
| Variable | `AWS_REGION` | `ap-south-1` |
| Variable | `TF_STATE_BUCKET` | `state_bucket` output |
| Variable | `DOMAIN_NAME` | `example.com` (your hosted zone) |
| Variable | `APP_SUBDOMAIN` | `app` |

Repository → **Settings → Environments → New environment** named `production`.
Optionally add yourself as a *required reviewer*, so every apply waits for manual approval.

No AWS access keys are stored in GitHub. Authentication uses short-lived OIDC tokens.

## 3. Push the code

```powershell
git init -b main
git add .
git commit -m "AWS infrastructure with Terraform and GitHub Actions"
git remote add origin https://github.com/jigneshpatel623-alt/aws-devops-task.git
git push -u origin main
```

## 4. Pipeline behaviour

| Event | Jobs |
|---|---|
| Pull request to `main` | fmt → validate → Checkov scan → plan (posted as PR comment) |
| Push / merge to `main` | fmt → validate → scan → plan → **apply** → health check |
| Manual: *Terraform Destroy* | destroy (requires typing `destroy`) |

The first apply takes about 15–20 minutes. RDS and ACM validation are the slowest steps.

## 5. (Optional) Run Terraform locally

```powershell
cd terraform/envs/dev
copy backend.hcl.example backend.hcl            # fill in bucket name
copy terraform.tfvars.example terraform.tfvars  # fill in domain
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

## 6. Validation checklist (take screenshots)

- [ ] `https://app.<domain>` loads and the browser shows a valid certificate
- [ ] `http://app.<domain>` redirects to HTTPS
- [ ] Refreshing shows different instance IDs / AZs (load balancing)
- [ ] Page shows **Database: Connected** and the visit counter increases
- [ ] EC2 → Target Groups → all targets **healthy**
- [ ] Terminate one instance → the ASG launches a replacement automatically
- [ ] S3 logs bucket contains `alb/AWSLogs/...` files (after ~5 min)
- [ ] RDS → *Publicly accessible: No*, *Encryption: Enabled*
- [ ] Secrets Manager shows `jignesh-devops-dev/rds/mysql`
- [ ] GitHub Actions run: all jobs green
- [ ] Session Manager: connect to an instance without SSH, then run `systemctl status webapp`

Command-line check:

```bash
bash scripts/health_check.sh https://app.<domain>
```

Save screenshots in `docs/screenshots/`.

## 7. Updating the application

Edit files in `app/` and push to `main`. Terraform uploads the new code to S3. The changed
content hash creates a new launch template version, and the ASG **instance refresh** replaces
instances one by one with no downtime.

## 8. Troubleshooting

| Symptom | Check |
|---|---|
| Targets unhealthy | Session Manager → `sudo cat /var/log/user-data.log`, `journalctl -u webapp` |
| Database shows "Unavailable" | Secret value, rds-sg rule, `curl localhost:8080/db-health` on the instance |
| ACM stuck *Pending validation* | Domain NS records must point to the Route 53 hosted zone |
| `AccessDenied` in GitHub Actions | `AWS_ROLE_ARN` secret; repo name must match the bootstrap `github_repo` |

## 9. Cleanup (avoid charges)

Run the **Terraform Destroy** workflow, or locally run `terraform destroy` in `terraform/envs/dev`.
The NAT Gateway, ALB and RDS are billed by the hour.
