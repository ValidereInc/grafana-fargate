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
  description         = "Key used to encrypt data in virtual analyzer monitoring database"
  enable_key_rotation = true
  multi_region = true

  tags = var.common_tags
}

resource "aws_kms_alias" "a" {
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias
  name          = "alias/${var.common_tags.environment}-${var.common_tags.service}-s3-kms-key"
  target_key_id = aws_kms_key.this.key_id
}

resource "aws_rds_cluster" "grafana" {
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster
  database_name          = "grafana"
  engine                 = "aurora-mysql"
  engine_version         = "5.7.mysql_aurora.2.11.2"
  master_username        = var.grafana_db_username
  master_password        = random_password.password.result
  storage_encrypted      = true
  db_subnet_group_name   = aws_db_subnet_group.grafana.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  skip_final_snapshot    = true
  kms_key_id             = aws_kms_key.this.key_id

  tags = var.do_backup ? merge(var.common_tags, {"backup-plan": var.common_tags.environment}) : var.common_tags

  lifecycle {
    create_before_destroy = true
    prevent_destroy       = false
  }
}

resource "aws_rds_cluster_instance" "grafana" {
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster_instance
  count = "1"

  cluster_identifier         = aws_rds_cluster.grafana.id
  identifier                 = "${var.resource_prefix}-grafana-${count.index}"
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

