# ----------------------------------------------------------------------------
# Database tier: Amazon RDS for PostgreSQL in isolated private subnets
# ----------------------------------------------------------------------------

resource "aws_db_subnet_group" "main" {
  name       = "${local.name}-db-subnets"
  subnet_ids = aws_subnet.db[*].id
  tags       = { Name = "${local.name}-db-subnets" }
}

# Enforce TLS for every connection (the app connects with sslmode=require).
resource "aws_db_parameter_group" "postgres" {
  name   = "${local.name}-pg16"
  family = "postgres16"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot" # how AWS records it; avoids a permanent diff (PG16's default is already 1)
  }
}

resource "aws_db_instance" "main" {
  identifier     = "${local.name}-db"
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage = 20 # free-tier limit
  storage_type      = "gp2"
  storage_encrypted = true # encryption at rest (AWS-managed KMS key)

  db_name  = "notes"
  username = "notesadmin"
  # RDS generates the password and stores it in Secrets Manager.
  # It never appears in Terraform code, state, CI/CD, or on the hosts' disks.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  parameter_group_name   = aws_db_parameter_group.postgres.name
  publicly_accessible    = false
  multi_az               = var.db_multi_az

  backup_retention_period         = var.db_backup_retention_days
  enabled_cloudwatch_logs_exports = ["postgresql"]
  auto_minor_version_upgrade      = true
  apply_immediately               = true

  # Coursework settings so `terraform destroy` works cleanly.
  # Production: deletion_protection = true, skip_final_snapshot = false.
  deletion_protection = false
  skip_final_snapshot = true

  tags = { Name = "${local.name}-db" }
}

locals {
  db_secret_arn = aws_db_instance.main.master_user_secret[0].secret_arn
}
