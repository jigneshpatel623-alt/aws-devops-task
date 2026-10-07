output "vpc_id" {
  value = aws_vpc.this.id
}

output "azs" {
  value = local.azs
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_app_subnet_ids" {
  value = aws_subnet.private_app[*].id
}

output "private_db_subnet_ids" {
  value = aws_subnet.private_db[*].id
}

output "nat_gateway_public_ips" {
  value = aws_eip.nat[*].public_ip
}
