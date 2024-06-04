data "aws_db_subnet_group" "grafana" {
  # create from platform
  name = "${var.environment}-${var.region}-grafana-aurora56"
}

resource "random_password" "password" {
  count   = var.is_backup ? 0 : 1
  length  = 16
  special = false
}

resource "aws_secretsmanager_secret" "creds" {
  count       = var.do_backup && !var.is_backup ? 1 : 0
  name        = "${var.common_tags.environment}-${var.common_tags.service}-grafana-backend-db-password"
  description = "Credential for Grafana MySQL backend"
  replica {
    region = var.dr_region
  }
}

resource "aws_secretsmanager_secret_version" "creds" {
  count         = var.do_backup && !var.is_backup ? 1 : 0
  secret_id     = aws_secretsmanager_secret.creds[0].id
  secret_string = random_password.password[0].result
}

data "aws_secretsmanager_secret_version" "creds" {
  count     = var.is_backup ? 1 : 0
  secret_id = "${var.common_tags.environment}-${var.common_tags.service}-grafana-backend-db-password"
}

resource "aws_kms_key" "this" {
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key
  count               = var.is_backup ? 0 : 1
  description         = "Key used to encrypt data in grafana database"
  enable_key_rotation = true
  multi_region        = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
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
      }
    ]
  })

  tags = var.common_tags
}

resource "aws_kms_alias" "a" {
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias
  count         = var.is_backup ? 0 : 1
  name          = "alias/${var.common_tags.environment}-${var.common_tags.service}-grafana-kms-key"
  target_key_id = aws_kms_key.this[0].key_id
}

resource "aws_kms_replica_key" "replica" {
  # https://registry.terraform.io/providers/hashicorp/awscc/latest/docs/resources/kms_replica_key
  provider        = aws.dr
  count           = var.do_backup && !var.is_backup ? 1 : 0
  primary_key_arn = aws_kms_key.this[0].arn

  tags = var.common_tags
}

resource "aws_kms_alias" "replica_alias" {
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias
  provider      = aws.dr
  count         = var.do_backup && !var.is_backup ? 1 : 0
  name          = "alias/${var.common_tags.environment}-${var.common_tags.service}-grafana-kms-key"
  target_key_id = aws_kms_replica_key.replica[0].key_id
}

resource "aws_rds_cluster" "grafana_encrypted" {
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster
  # if this is the backup, we don't provision the cluster because it will be done via the restore job (click-ops)
  count = var.is_backup ? 0 : 1

  cluster_identifier      = "${var.common_tags.environment}-grafana-monitoring-db-cluster"
  database_name           = "grafana"
  engine                  = "aurora-mysql"
  engine_version          = "5.7.mysql_aurora.2.11.5"
  availability_zones      = var.availability_zones
  master_username         = var.grafana_db_username
  master_password         = var.is_backup ? data.aws_secretsmanager_secret_version.creds[0].secret_string : random_password.password[0].result
  storage_encrypted       = true
  db_subnet_group_name    = data.aws_db_subnet_group.grafana.name
  vpc_security_group_ids  = [var.grafana_rds_security_group_id]
  skip_final_snapshot     = true
  kms_key_id              = aws_kms_key.this[0].arn
  backup_retention_period = var.db_backup_retention_period

  tags = var.do_backup ? merge(var.common_tags, { "backup-plan" : var.common_tags.environment }) : var.common_tags

  lifecycle {
    create_before_destroy = true
    prevent_destroy       = false
    ignore_changes = [
      engine_version,
    ]
  }
}

data "aws_rds_cluster" "restored" {
  # if this is the backup, we read in the restored cluster
  count              = var.is_backup ? 1 : 0
  cluster_identifier = "${var.common_tags.environment}-grafana-monitoring-db-cluster"
}

resource "aws_rds_cluster_instance" "grafana_encrypted" {
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster_instance
  for_each = toset(var.availability_zones)

  cluster_identifier         = var.is_backup ? data.aws_rds_cluster.restored[0].cluster_identifier : aws_rds_cluster.grafana_encrypted[0].cluster_identifier
  identifier                 = "${var.common_tags.environment}-grafana-monitoring-db-${each.key}"
  engine                     = "aurora-mysql"
  engine_version             = "5.7.mysql_aurora.2.11.5"
  instance_class             = var.db_instance_type
  publicly_accessible        = false
  db_subnet_group_name       = data.aws_db_subnet_group.grafana.name
  auto_minor_version_upgrade = true

  tags = var.do_backup ? merge(var.common_tags, { "backup-plan" : var.common_tags.environment }) : var.common_tags

  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      engine_version,
    ]
  }
}