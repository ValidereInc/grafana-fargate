locals {
  grafana_config = {
    GF_SERVER_DOMAIN     = "${var.grafana_subdomain}.${var.dns_name}"
    GF_SERVER_ROOT_URL   = "https://${var.grafana_subdomain}.${var.dns_name}"
    GF_DATABASE_USER     = var.grafana_db_username
    GF_DATABASE_TYPE     = "mysql"
    GF_DATABASE_HOST     = var.is_backup ? "${data.aws_rds_cluster.restored[0].endpoint}:3306" : "${aws_rds_cluster.grafana_encrypted[0].endpoint}:3306"
    GF_LOG_LEVEL         = var.grafana_log_level
    GF_DATABASE_PASSWORD = var.is_backup ? data.aws_secretsmanager_secret_version.creds[0].secret_string : random_password.password[0].result
    ### AUTH
    GF_AUTH_GENERIC_OAUTH_ENABLED               = "True"
    GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP         = "True"
    GF_AUTH_GENERIC_OAUTH_TEAM_IDS              = ""
    GF_AUTH_GENERIC_OAUTH_ALLOWED_ORGANIZATIONS = ""
    GF_AUTH_GENERIC_OAUTH_NAME                  = var.oauth_name
    GF_AUTH_GENERIC_OAUTH_CLIENT_ID             = var.oauth_client_id
    GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET         = var.oauth_client_secret
    GF_AUTH_GENERIC_OAUTH_SCOPES                = "openid profile email"
    GF_AUTH_GENERIC_OAUTH_AUTH_URL              = "https://${var.oauth_domain}/authorize"
    GF_AUTH_GENERIC_OAUTH_TOKEN_URL             = "https://${var.oauth_domain}/oauth/token"
    GF_AUTH_GENERIC_OAUTH_API_URL               = "https://${var.oauth_domain}/userinfo"
    GF_AUTH_GENERIC_OAUTH_USE_PKCE              = "True"
  }
}
resource "aws_ecs_cluster" "grafana" {
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster
  name = "${var.resource_prefix}-grafana-cluster"
  tags = var.common_tags
}

resource "aws_ecs_task_definition" "grafana" {
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition
  family = "${var.resource_prefix}-grafana_task_definition"
  container_definitions = jsonencode([
    {
      name      = "${var.resource_prefix}-grafana"
      image     = var.image_url
      essential = true
      portMappings = [
        {
          hostPost      = 3000
          containerPort = 3000
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.grafana.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "${var.resource_prefix}-grafana"
        }
      }
      environment = [
        for key in keys(local.grafana_config) :
        {
          name  = key,
          value = lookup(local.grafana_config, key)
        }
      ]
      readonlyRootFilesystem = true
    }
  ])
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024
  task_role_arn            = aws_iam_role.grafana_ecs_task.arn
  execution_role_arn       = aws_iam_role.grafana_ecs_task_execution.arn
  network_mode             = "awsvpc"

  lifecycle {
    create_before_destroy = true
  }

  tags = var.common_tags
}

resource "aws_ecs_service" "grafana" {
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service
  name            = "${var.resource_prefix}-grafana"
  cluster         = aws_ecs_cluster.grafana.name
  task_definition = aws_ecs_task_definition.grafana.arn
  desired_count   = var.grafana_count
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200


  network_configuration {
    security_groups = [var.grafana_ecs_security_group_id]
    subnets         = var.subnets
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.grafana.arn
    container_name   = "${var.resource_prefix}-grafana"
    container_port   = 3000
  }

  depends_on = [aws_lb.grafana]

  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_log_group" "grafana" {
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group
  name = "${var.resource_prefix}-grafana"
  tags = var.common_tags
}
