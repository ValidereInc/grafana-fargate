locals {
  access_logs_bucket_name = "${var.common_tags.environment}-grafana-alb-access-logs-${var.region}"
}

resource "aws_kms_key" "aws_lb_logs" {
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key
  description         = "KMS Key for encrypting grafana alb access logs"
  key_usage           = "ENCRYPT_DECRYPT"
  enable_key_rotation = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action = [
          "kms:Create*",
          "kms:Describe*",
          "kms:Enable*",
          "kms:List*",
          "kms:Put*",
          "kms:Update*",
          "kms:Revoke*",
          "kms:Disable*",
          "kms:Get*",
          "kms:Delete*",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion",
          "kms:ReplicateKey",
          "kms:Decrypt*",
          "kms:Encrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:TagResource",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = [
          "kms:Create*",
          "kms:Decrypt*",
          "kms:Describe*",
          "kms:Encrypt*",
          "kms:Get*",
          "kms:List*",
          "kms:ReEncrypt*",
          "kms:Sign",
          "kms:Verify*",
          "kms:GenerateDataKey*",
        ]
        Resource = "*"
      }
    ]
  })

  tags = var.common_tags
}

resource "aws_kms_alias" "aws_lb_logs" {
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias
  name          = "alias/${var.common_tags.environment}-grafana-alb-access-logs-s3-bucket-key"
  target_key_id = aws_kms_key.aws_alb_access_logs_bucket.id
}

resource "aws_s3_bucket" "aws_lb_logs" {
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket 
  bucket        = local.access_logs_bucket_name
  force_destroy = false

  tags = var.do_backup ? merge(var.common_tags, { "backup-plan" : var.common_tags.environment }) : var.common_tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "aws_lb_logs" {
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration
  bucket = aws_s3_bucket.aws_lb_logs.id

  rule {
    bucket_key_enabled = true
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.aws_alb_access_logs_bucket.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "aws_lb_logs" {
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls
  bucket = aws_s3_bucket.aws_lb_logs.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "aws_lb_logs" {
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block
  bucket = aws_s3_bucket.aws_lb_logs.bucket

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "aws_lb_logs" {
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning
  bucket = aws_s3_bucket.aws_lb_logs.bucket
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_lb" "grafana" {
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb
  name            = "${var.resource_prefix}-grafana"
  internal        = "false"
  security_groups = [var.grafana_alb_security_group_id]
  subnets         = var.lb_subnets
  idle_timeout    = "3600"

  enable_deletion_protection = false

  access_logs {
    bucket  = aws_s3_bucket.aws_lb_logs.id
    prefix  = "${local.access_logs_bucket_name}/"
    enabled = true
  }

  tags = var.common_tags
}

resource "aws_lb_listener" "front_end_https" {
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener
  load_balancer_arn = aws_lb.grafana.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.cert_arn

  default_action {
    target_group_arn = aws_lb_target_group.grafana.arn
    type             = "forward"
  }
  tags = var.common_tags
}

resource "aws_lb_target_group" "grafana" {
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group
  name                 = "${var.resource_prefix}-grafana-tg"
  port                 = 3000
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = 30

  health_check {
    interval            = 10
    path                = "/login"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    protocol            = "HTTP"
  }

  tags = var.common_tags
}
