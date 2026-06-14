output "project" {
  description = "Project name"
  value       = "reb-elearning"
}

output "environment" {
  description = "Environment"
  value       = var.environment
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnets" {
  description = "Public subnets"
  value       = module.vpc.public_subnets
}

output "private_subnets" {
  description = "Private subnets"
  value       = module.vpc.private_subnets
}

output "lb_dns_name" {
  description = "Load balancer DNS name"
  value       = aws_lb.app.dns_name
}

output "lb_zone_id" {
  description = "Load balancer zone ID for DNS"
  value       = aws_lb.app.zone_id
}

output "mysql_endpoint" {
  description = "MySQL endpoint"
  value       = aws_db_instance.mysql.endpoint
}

output "mysql_address" {
  description = "MySQL address"
  value       = aws_db_instance.mysql.address
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = aws_elasticache_replication_group.redis.configuration_endpoint_address
}

output "redis_port" {
  description = "Redis port"
  value       = aws_elasticache_replication_group.redis.configuration_endpoint_port
}

output "s3_bucket" {
  description = "S3 bucket name for moodledata"
  value       = aws_s3_bucket.moodledata.id
}

output "app_security_group_id" {
  description = "App security group ID"
  value       = aws_security_group.app.id
}
