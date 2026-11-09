variable "project" {
  description = "Name prefix for every resource."
  type        = string
  default     = "notes"
}

variable "aws_region" {
  description = "AWS region. ap-south-1 (Mumbai) is the closest region to Pakistan (lowest latency)."
  type        = string
  default     = "ap-south-1"
}

variable "github_repo" {
  description = "GitHub repository allowed to deploy, as \"owner/name\" (e.g. \"ahmer/cloud-notes\")."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repo))
    error_message = "github_repo must look like owner/name."
  }
}

variable "create_github_oidc_provider" {
  description = "Set to false if this AWS account already has the GitHub OIDC provider (token.actions.githubusercontent.com)."
  type        = bool
  default     = true
}

# ---------- network ----------
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnets (ALB, NAT gateway) - one per AZ."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "app_subnet_cidrs" {
  description = "Private subnets for the container hosts (web + app tiers) - one per AZ."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "db_subnet_cidrs" {
  description = "Isolated private subnets for RDS (no internet route at all) - one per AZ."
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24"]
}

# ---------- compute ----------
variable "instance_type" {
  description = "Free-tier eligible instance type."
  type        = string
  default     = "t3.micro"
}

variable "asg_min_size" {
  type    = number
  default = 2
}

variable "asg_desired_capacity" {
  type    = number
  default = 2
}

variable "asg_max_size" {
  type    = number
  default = 4
}

variable "cpu_target_percent" {
  description = "Target average CPU for the target-tracking scaling policy."
  type        = number
  default     = 50
}

variable "docker_compose_version" {
  description = "Docker Compose plugin release installed on the hosts."
  type        = string
  default     = "v2.29.7"
}

# ---------- database ----------
variable "db_instance_class" {
  description = "Free-tier eligible RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "db_engine_version" {
  type    = string
  default = "16"
}

variable "db_multi_az" {
  description = "Multi-AZ standby for automatic failover. Not free-tier - enable for production."
  type        = bool
  default     = false
}

variable "db_backup_retention_days" {
  description = "Automated backup retention. Free-tier accounts may be limited to 1 day."
  type        = number
  default     = 1
}

variable "log_retention_days" {
  type    = number
  default = 7
}
