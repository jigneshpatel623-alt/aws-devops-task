output "secret_arn" {
  value = aws_secretsmanager_secret.db.arn
}

output "db_password" {
  value     = random_password.db.result
  sensitive = true
}
