variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  description = "Environment name (prod, staging, dev)"
  type        = string
  default     = "prod"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.large"
}

variable "db_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 100
}

variable "db_password" {
  description = "Database root password"
  type        = string
  sensitive   = true
  default     = "changeme-secure-password"
}

variable "db_username" {
  description = "Database username"
  type        = string
  default     = "moodleuser"
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "moodle"
}

variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t3.micro"
}

variable "app_instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "asg_min_size" {
  description = "Auto Scaling Group min size"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Auto Scaling Group max size"
  type        = number
  default     = 10
}

variable "asg_desired_capacity" {
  description = "Auto Scaling Group desired capacity"
  type        = number
  default     = 2
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Domain name for the load balancer"
  type        = string
  default     = "moodle.example.com"
}

variable "ssl_email" {
  description = "Email for SSL certificate"
  type        = string
  default     = "admin@example.com"
}
