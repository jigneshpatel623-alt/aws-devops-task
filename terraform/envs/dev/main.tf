data "aws_caller_identity" "current" {}

# Latest Amazon Linux 2023 AMI
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  name_prefix = "${var.project}-${var.environment}"
  use_domain  = var.domain_name != ""
  app_fqdn    = local.use_domain ? "${var.app_subdomain}.${var.domain_name}" : module.alb.alb_dns_name
  app_port    = 8080

  # Application source shipped to the app bucket; any change rolls the ASG
  app_src_dir = "${path.module}/../../../app"
  app_files   = toset([for f in fileset(local.app_src_dir, "**") : f if !strcontains(f, "__pycache__")])
  app_version = sha1(join(",", [for f in sort(tolist(local.app_files)) : filemd5("${local.app_src_dir}/${f}")]))
}

# 1. Networking
module "vpc" {
  source             = "../../modules/vpc"
  name               = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  az_count           = 2
  single_nat_gateway = var.single_nat_gateway
}

# 2. Security groups
module "security_groups" {
  source   = "../../modules/security-groups"
  name     = local.name_prefix
  vpc_id   = module.vpc.vpc_id
  app_port = local.app_port
}

# 3. Customer-managed KMS key (Secrets Manager, RDS, app bucket)
module "kms" {
  source      = "../../modules/kms"
  name_prefix = local.name_prefix
}

# 3b. S3 buckets (app storage + ALB logs)
module "s3" {
  source      = "../../modules/s3"
  name_prefix = local.name_prefix
  account_id  = data.aws_caller_identity.current.account_id
  kms_key_arn = module.kms.key_arn
}

resource "aws_s3_object" "app" {
  for_each = local.app_files

  bucket = module.s3.app_bucket_id
  key    = "app/${each.value}"
  source = "${local.app_src_dir}/${each.value}"
  etag   = filemd5("${local.app_src_dir}/${each.value}")
}

# 4. Database credentials (Secrets Manager)
module "secrets" {
  source      = "../../modules/secrets"
  name_prefix = local.name_prefix
  db_username = var.db_username
  db_name     = var.db_name
  db_host     = module.rds.address
  db_port     = module.rds.port
  kms_key_arn = module.kms.key_arn
}

# 5. RDS MySQL (private DB subnets)
module "rds" {
  source              = "../../modules/rds"
  name_prefix         = local.name_prefix
  subnet_ids          = module.vpc.private_db_subnet_ids
  security_group_id   = module.security_groups.rds_sg_id
  db_name             = var.db_name
  username            = var.db_username
  password            = module.secrets.db_password
  instance_class      = var.db_instance_class
  multi_az            = var.db_multi_az
  kms_key_arn         = module.kms.key_arn
  deletion_protection = var.deletion_protection
}

# 6. IAM for EC2
module "iam" {
  source         = "../../modules/iam"
  name_prefix    = local.name_prefix
  secret_arn     = module.secrets.secret_arn
  app_bucket_arn = module.s3.app_bucket_arn
  kms_key_arn    = module.kms.key_arn
  region         = var.aws_region
}

# 7. TLS certificate
module "acm" {
  source      = "../../modules/acm"
  domain_name = var.domain_name
  fqdn        = local.app_fqdn
}

# 8. Application Load Balancer (HTTPS)
module "alb" {
  source              = "../../modules/alb"
  name_prefix         = local.name_prefix
  vpc_id              = module.vpc.vpc_id
  public_subnet_ids   = module.vpc.public_subnet_ids
  security_group_id   = module.security_groups.alb_sg_id
  certificate_arn     = module.acm.certificate_arn
  logs_bucket         = module.s3.logs_bucket_id
  logs_prefix         = module.s3.logs_prefix
  app_port            = local.app_port
  deletion_protection = var.deletion_protection
  create_dns_record   = local.use_domain
  zone_id             = module.acm.zone_id
  fqdn                = local.app_fqdn
}

# 9. Auto Scaling Group with Launch Template
module "asg" {
  source                = "../../modules/asg"
  name_prefix           = local.name_prefix
  ami_id                = data.aws_ssm_parameter.al2023.insecure_value
  instance_type         = var.instance_type
  security_group_id     = module.security_groups.app_sg_id
  instance_profile_name = module.iam.instance_profile_name
  private_subnet_ids    = module.vpc.private_app_subnet_ids
  target_group_arns     = [module.alb.target_group_arn]
  min_size              = var.asg_min_size
  max_size              = var.asg_max_size
  desired_capacity      = var.asg_desired_capacity

  user_data = templatefile("${path.module}/../../../scripts/user_data.sh", {
    region      = var.aws_region
    app_bucket  = module.s3.app_bucket_id
    secret_arn  = module.secrets.secret_arn
    app_version = local.app_version
  })

  # App code must be in S3 and the DB reachable before instances boot
  depends_on = [aws_s3_object.app, module.rds, module.secrets]
}
