data "aws_caller_identity" "current" {}

# Rôle imposé par le Learner Lab : la création de rôles IAM y est interdite.
data "aws_iam_role" "lab" {
  name = "LabRole"
}

# Dépôt d'images créé par infra/bootstrap.
data "aws_ecr_repository" "app" {
  name = "password-checker"
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  azs        = var.availability_zones

  # Bucket de journaux créé par infra/bootstrap.
  logs_bucket = "devsecops-logs-${local.account_id}"

  container_port = 8080
  image          = "${data.aws_ecr_repository.app.repository_url}:${var.image_tag}"
}
