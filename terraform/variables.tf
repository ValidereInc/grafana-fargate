variable "common_tags" {
  type = object({
    service     = string
    environment = string
    managed-via = string
  })
}

variable "environment" {
  description = "The (abbreviated name) of the environment to deploy to"
  default     = "dev"
}

variable "region" {
  default     = "us-east-1"
  description = "The primary AWS region"
}

variable "resource_prefix" {
  description = "A prefix to add to resource names. e.g. integration-<resource-name>"
  type        = string
}

variable "account_id" {
  default = ""
}

variable "grafana_alb_security_group_id" {
  description = "id of the security group for the Grafana alb"
}

variable "grafana_ecs_security_group_id" {
  description = "id of the security group for the Grafana ecs"
}

variable "grafana_rds_security_group_id" {
  description = "id of the security group for the Grafana rds cluster"
}

variable "dns_name" {
  description = "The DNS name for the zone"
  default     = ""
}

variable "grafana_subdomain" {
  description = "The subdomain to use for Grafana. <grafana_subdomain>.<dns_name>"
  type        = string
}

variable "cert_arn" {
  description = "the certificate arn that is associated with the dns_name"
  default     = ""
}

variable "vpc_id" {
  description = "The vpc id where grafana will be deployed"
  default     = ""
}

variable "subnets" {
  description = "the subnets used for the grafana task"
  default     = [""]
}

variable "lb_subnets" {
  description = "the load balancer subnets"
  default     = [""]
}

variable "db_subnet_ids" {
  description = "the subnets to launch the Aurora databse"
  default     = [""]
}

variable "db_instance_type" {
  description = "the instance size for the Aurora database"
  default     = "db.t2.small"
}

variable "db_backup_retention_period" {
  description = "value in days for the backup retention period"
  default     = 5

}

variable "image_url" {
  description = "the image url for the grafana image"
  default     = "grafana/grafana:8.2.6"
}

variable "grafana_count" {
  default = "1"
}

variable "grafana_db_username" {
  type        = string
  description = "The username to use for the Grafana db backend"
}

variable "grafana_log_level" {
  type        = string
  description = "The log level for the Grafana application"
  default     = "INFO"
}

variable "oauth_name" {
  type        = string
  description = "The name to use for OAuth (for identification)"
}

variable "oauth_domain" {
  type        = string
  description = "The domain for OAuth. Will be used to call authorize, token, and userinfo endpoints"
}

variable "oauth_client_id" {
  type        = string
  description = "The client ID for OAuth"
}

variable "oauth_client_secret" {
  type        = string
  description = "The client secret for OAuth"
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID"
  type        = string
}

variable "cloudflare_record_name" {
  description = "DNS record name, including subdomain, not including the domain"
  type        = string
}

variable "cloudflare_record_tags" {
  description = "Tags for cloudflare DNS record"
  type        = list(string)
}

variable "do_backup" {
  description = "controls whether RDS isntance is backed up through AWS backup via backup-plan tag"
  type        = bool
  default     = true
}

variable "dr_region" {
  description = "region to which to replicate kms key"
  type        = string
  default     = "us-east-2"
}

variable "is_backup" {
  description = "specifies if the deployment is a disaster recovery backup. Controls creation of certain resources like KMS keys."
  type        = bool
  default     = false
}

variable "availability_zones" {
  description = "availability zones to use for the RDS cluster instances"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "alb_access_logs_bucket_name" {
  description = "bucket in which to store alb access logs"
  type        = string
}