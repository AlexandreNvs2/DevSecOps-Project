output "state_bucket" {
  description = "Bucket de l'état, à passer à « terraform init -backend-config »."
  value       = aws_s3_bucket.state.id
}

output "state_kms_key_arn" {
  description = "Clé KMS qui chiffre l'état."
  value       = aws_kms_key.state.arn
}

output "region" {
  value = var.region
}
