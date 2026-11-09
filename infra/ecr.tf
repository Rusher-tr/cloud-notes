# ----------------------------------------------------------------------------
# Container registry: one private ECR repository per tier
# ----------------------------------------------------------------------------

resource "aws_ecr_repository" "repo" {
  for_each = toset(["web", "app"])

  name                 = "${local.name}-${each.key}"
  image_tag_mutability = "MUTABLE" # "latest" moves; every build is also tagged with its commit SHA
  force_delete         = true      # lets `terraform destroy` remove repos that still hold images

  image_scanning_configuration {
    scan_on_push = true # free basic vulnerability scan of every pushed image
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Cost control: keep only the 10 most recent images per repository.
resource "aws_ecr_lifecycle_policy" "repo" {
  for_each   = aws_ecr_repository.repo
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
