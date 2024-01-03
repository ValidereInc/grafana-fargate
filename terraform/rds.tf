resource "aws_security_group" "rds" {
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group
  name_prefix = "${var.resource_prefix}-grafana-aurora56"
  description = "RDS Aurora access from internal security groups"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow 3306 from defined security groups"
    protocol    = "tcp"
    from_port   = 3306
    to_port     = 3306

    security_groups = [
      var.grafana_ecs_security_group_id,
    ]
  }
  tags = var.common_tags
}

resource "aws_db_subnet_group" "grafana" {
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group
  name        = "${var.resource_prefix}-grafana-aurora56"
  description = "Subnets to launch RDS database into"
  subnet_ids  = var.db_subnet_ids

  tags = var.common_tags
}

resource "random_password" "password" {
  length  = 16
  special = false
}

resource "aws_secretsmanager_secret" "creds" {
  name        = "${var.resource_prefix}-grafana-backend-db"
  description = "Credential for Grafana MySQL backend"
}

resource "aws_secretsmanager_secret_version" "creds" {
  secret_id     = aws_secretsmanager_secret.creds.id
  secret_string = random_password.password.result
}

resource "aws_kms_key" "this" {
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key
  count               = var.is_backup ? 0 : 1
  description         = "Key used to encrypt data in grafana database"
  enable_key_rotation = true
  multi_region        = true

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

data "aws_kms_key" "replica" {
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/kms_key
  # if deploying backup, use existing multi-region kms key (must have already been deployed)
  count  = var.is_backup ? 1 : 0
  key_id = "alias/${var.common_tags.environment}-${var.common_tags.service}-grafana-kms-key"
}

resource "aws_rds_cluster" "grafana_encrypted" {
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster
  database_name           = "grafana"
  engine                  = "aurora-mysql"
  engine_version          = "5.7.mysql_aurora.2.11.2"
  master_username         = var.grafana_db_username
  master_password         = random_password.password.result
  storage_encrypted       = true
  db_subnet_group_name    = aws_db_subnet_group.grafana.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  skip_final_snapshot     = true
  kms_key_id              = var.is_backup ? data.aws_kms_key.replica[0].arn : aws_kms_key.this[0].arn
  backup_retention_period = 5

  tags = var.do_backup ? merge(var.common_tags, { "backup-plan" : var.common_tags.environment }) : var.common_tags

  lifecycle {
    create_before_destroy = true
    prevent_destroy       = false
  }
}

resource "aws_rds_cluster_instance" "grafana_encrypted" {
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster_instance

  cluster_identifier         = aws_rds_cluster.grafana_encrypted.id
  identifier                 = "${var.common_tags.environment}-grafana-monitoring-db"
  engine                     = "aurora-mysql"
  engine_version             = "5.7.mysql_aurora.2.11.2"
  instance_class             = var.db_instance_type
  publicly_accessible        = false
  db_subnet_group_name       = aws_db_subnet_group.grafana.name
  auto_minor_version_upgrade = true

  tags = var.common_tags

  lifecycle {
    create_before_destroy = true
  }
}