output "state_bucket" {
  description = "Bucket de l'état, à passer à « terraform init -backend-config »."
  value       = local.state_name
}

output "state_kms_key_arn" {
  description = "Clé KMS qui chiffre l'état."
  value       = aws_kms_key.state.arn
}

output "region" {
  value = var.region
}

output "ecr_repository_url" {
  description = "Adresse du dépôt ECR de l'image de l'application."
  value       = aws_ecr_repository.app.repository_url
}

output "app_logs_bucket" {
  description = "Bucket des journaux de l'ALB et du VPC."
  value       = local.app_logs_name
}
