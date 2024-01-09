// lb dns
output "grafana_rds" {
  value = var.is_backup ? data.aws_rds_cluster.restored[0].endpoint : aws_rds_cluster.grafana_encrypted[0].endpoint
}

output "grafana_role" {
  value = aws_iam_role.grafana_assume.arn
}

