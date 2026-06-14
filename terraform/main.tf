terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.aws_region
}

locals {
  project_name = "reb-elearning"
  environment  = var.environment
}

# VPC
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name = "${local.project_name}-${local.environment}-vpc"
  cidr = "10.0.0.0/16"

  azs             = var.availability_zones
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = var.environment == "prod" ? false : true
  enable_dns_hostnames   = true
  enable_dns_support     = true

  tags = {
    Project     = local.project_name
    Environment = local.environment
  }
}

# Security Groups
resource "aws_security_group" "lb" {
  name_prefix = "${local.project_name}-${local.environment}-lb-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Project = local.project_name, Environment = local.environment }
}

resource "aws_security_group" "app" {
  name_prefix = "${local.project_name}-${local.environment}-app-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 9000
    to_port         = 9000
    protocol        = "tcp"
    security_groups = [aws_security_group.lb.id]
  }
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.lb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Project = local.project_name, Environment = local.environment }
}

resource "aws_security_group" "db" {
  name_prefix = "${local.project_name}-${local.environment}-db-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
  tags = { Project = local.project_name, Environment = local.environment }
}

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${local.project_name}-${local.environment}"
  subnet_ids = module.vpc.private_subnets
  tags = {
    Project     = local.project_name
    Environment = local.environment
  }
}

# RDS MySQL 8.4
resource "aws_db_instance" "mysql" {
  identifier             = "${local.project_name}-${local.environment}-mysql"
  engine                 = "mysql"
  engine_version         = "8.4"
  instance_class         = var.db_instance_class
  allocated_storage      = var.db_allocated_storage
  storage_type           = "gp3"
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  skip_final_snapshot    = var.environment != "prod"
  deletion_protection    = var.environment == "prod"
  backup_retention_period = var.environment == "prod" ? 7 : 1
  multi_az               = var.environment == "prod"
  tags = {
    Project     = local.project_name
    Environment = local.environment
  }
}

# ElastiCache Redis
resource "aws_elasticache_subnet_group" "redis" {
  name       = "${local.project_name}-${local.environment}-redis"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id         = "${local.project_name}-${local.environment}-redis"
  description                  = "Redis cluster for Moodle sessions"
  engine                       = "redis"
  engine_version               = "7.1"
  node_type                    = var.redis_node_type
  num_cache_clusters           = var.environment == "prod" ? 3 : 1
  parameter_group_name         = "default.redis7"
  subnet_group_name            = aws_elasticache_subnet_group.redis.name
  security_group_ids           = [aws_security_group.db.id]
  at_rest_encryption_enabled   = true
  transit_encryption_enabled   = true
  automatic_failover_enabled   = var.environment == "prod"
  tags = {
    Project     = local.project_name
    Environment = local.environment
  }
}

# Application Auto Scaling Group
resource "aws_launch_template" "app" {
  name_prefix   = "${local.project_name}-${local.environment}-app-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.app_instance_type
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }
  user_data = base64encode(templatefile("${path.module}/../ansible/files/user-data.sh", {}))
  tags = {
    Project     = local.project_name
    Environment = local.environment
  }
}

resource "aws_autoscaling_group" "app" {
  name                = "${local.project_name}-${local.environment}-app-asg"
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  desired_capacity    = var.asg_desired_capacity
  vpc_zone_identifier = module.vpc.private_subnets
  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }
  target_group_arns = [aws_lb_target_group.app.arn]
  health_check_type = "ELB"
  health_check_grace_period = 300
  tag {
    key                 = "Project"
    value               = local.project_name
    propagate_at_launch = true
  }
  tag {
    key                 = "Environment"
    value               = local.environment
    propagate_at_launch = true
  }
}

# Load Balancer
resource "aws_lb" "app" {
  name               = "${local.project_name}-${local.environment}-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb.id]
  subnets            = module.vpc.public_subnets
  tags = {
    Project     = local.project_name
    Environment = local.environment
  }
}

resource "aws_lb_target_group" "app" {
  name     = "${local.project_name}-${local.environment}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id
  health_check {
    path                = "/"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
  tags = {
    Project     = local.project_name
    Environment = local.environment
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.app.arn
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = var.certificate_arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# Data sources
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "app" {
  name = "${local.project_name}-${local.environment}-app-profile"
  role = aws_iam_role.app.name
}

resource "aws_iam_role" "app" {
  name = "${local.project_name}-${local.environment}-app-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
  tags = { Project = local.project_name, Environment = local.environment }
}

resource "aws_iam_role_policy_attachment" "app_ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# S3 Bucket for moodledata
resource "aws_s3_bucket" "moodledata" {
  bucket = "${local.project_name}-${local.environment}-moodledata"
  tags = {
    Project     = local.project_name
    Environment = local.environment
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "moodledata" {
  bucket = aws_s3_bucket.moodledata.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

output "lb_dns_name" {
  description = "Load balancer DNS name"
  value       = aws_lb.app.dns_name
}

output "mysql_endpoint" {
  description = "MySQL endpoint"
  value       = aws_db_instance.mysql.endpoint
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = aws_elasticache_replication_group.redis.configuration_endpoint_address
}

output "s3_bucket" {
  description = "S3 bucket name for moodledata"
  value       = aws_s3_bucket.moodledata.id
}
