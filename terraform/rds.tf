resource "aws_security_group" "rds" {
  name_prefix = "${var.resource_prefix}-grafana-aurora56"
  description = "RDS Aurora access from internal security groups"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow 3306 from defined security groups"
    protocol    = "tcp"
    from_port   = 3306
    to_port     = 3306

    security_groups = [
      aws_security_group.grafana_ecs.id,
    ]
  }

  tags = {
    Name        = "${var.resource_prefix}-grafana-aurora56"
    Description = "RDS Aurora access from internal security groups"
    ManagedBy   = "Terraform"
  }
}

resource "aws_db_subnet_group" "grafana" {
  name        = "${var.resource_prefix}-grafana-aurora56"
  description = "Subnets to launch RDS database into"
  subnet_ids  = var.db_subnet_ids

  tags = {
    Name        = "grafana-aurora56-subnet-group"
    Description = "Subnets to use for RDS databases"
    ManagedBy   = "Terraform"
  }
}

data "aws_secretsmanager_secret_version" "grafana_db_backend" {
  secret_id = "${var.resource_prefix}-grafana-backend-db-creds"
}

resource "aws_rds_cluster" "grafana" {
  engine                 = "aurora"
  database_name          = "grafana"
  master_username        = var.grafana_db_username
  master_password        = jsondecode(data.aws_secretsmanager_secret_version.grafana_db_backend.secret_string).password
  storage_encrypted      = true
  db_subnet_group_name   = aws_db_subnet_group.grafana.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  skip_final_snapshot    = true

  tags = {
    Name        = "${var.resource_prefix}-grafana"
    Description = "RDS Aurora cluster for the grafana environment"
    ManagedBy   = "Terraform"
  }

  lifecycle {
    create_before_destroy = true
    prevent_destroy       = false
  }
}

resource "aws_rds_cluster_instance" "grafana" {
  count = "1"

  cluster_identifier         = aws_rds_cluster.grafana.id
  identifier                 = "${var.resource_prefix}-grafana-${count.index}"
  engine                     = "aurora"
  instance_class             = var.db_instance_type
  publicly_accessible        = false
  db_subnet_group_name       = aws_db_subnet_group.grafana.name
  auto_minor_version_upgrade = true

  tags = {
    Name        = "${var.resource_prefix}-grafana-aurora-instance"
    Description = "RDS Aurora cluster for the grafana environment"
    ManagedBy   = "Terraform"
  }

  lifecycle {
    create_before_destroy = true
  }
}

