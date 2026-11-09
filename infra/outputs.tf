output "app_url" {
  description = "Open this in a browser."
  value       = "http://${aws_lb.main.dns_name}"
}

output "asg_name" {
  value = aws_autoscaling_group.app.name
}

output "ecr_repositories" {
  value = { for k, r in aws_ecr_repository.repo : k => r.repository_url }
}

output "db_endpoint" {
  description = "Private endpoint - not reachable from the internet."
  value       = aws_db_instance.main.address
}

output "db_secret_arn" {
  value = local.db_secret_arn
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}

output "github_setup_commands" {
  description = "Run these from the repository folder (needs `gh auth login`) to configure the pipeline."
  value       = <<-EOT
    gh secret set AWS_ROLE_ARN --body "${aws_iam_role.github_actions.arn}"
    gh variable set AWS_REGION --body "${var.aws_region}"
    gh variable set ECR_WEB_REPOSITORY --body "${aws_ecr_repository.repo["web"].name}"
    gh variable set ECR_APP_REPOSITORY --body "${aws_ecr_repository.repo["app"].name}"
    gh variable set ASG_NAME --body "${aws_autoscaling_group.app.name}"
    gh variable set APP_URL --body "http://${aws_lb.main.dns_name}"
  EOT
}
