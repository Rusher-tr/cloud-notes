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
  # Uses `gh api` so it also works with old gh versions that lack `gh variable`.
  # Each variable is updated if it exists (PATCH) or created otherwise (POST).
  value = <<-EOT
    gh secret set AWS_ROLE_ARN --body "${aws_iam_role.github_actions.arn}"
    setvar() { gh api -X PATCH "repos/${var.github_repo}/actions/variables/$1" -f name="$1" -f value="$2" >/dev/null 2>&1 || gh api -X POST "repos/${var.github_repo}/actions/variables" -f name="$1" -f value="$2" >/dev/null && echo "set $1"; }
    setvar AWS_REGION "${var.aws_region}"
    setvar ECR_WEB_REPOSITORY "${aws_ecr_repository.repo["web"].name}"
    setvar ECR_APP_REPOSITORY "${aws_ecr_repository.repo["app"].name}"
    setvar ASG_NAME "${aws_autoscaling_group.app.name}"
    setvar APP_URL "http://${aws_lb.main.dns_name}"
  EOT
}
