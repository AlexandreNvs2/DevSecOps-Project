# Tests du module bootstrap, sans compte AWS : le fournisseur est simulé
# (mock_provider), « apply » ne crée rien et calcule des valeurs factices.
# Ils prouvent que les garanties justifiant les exceptions Checkov sont
# bien en place.
#
# Lancement : terraform init -backend=false && terraform test

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}

run "etat_protege" {
  command = apply

  assert {
    condition     = aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled"
    error_message = "L'état doit être versionné (restauration après erreur, compense l'absence de réplication)."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.state.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "aws:kms"
    error_message = "L'état doit être chiffré avec KMS."
  }

  assert {
    condition     = aws_kms_key.state.enable_key_rotation == true
    error_message = "La rotation de la clé KMS doit être activée."
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.state.block_public_acls,
      aws_s3_bucket_public_access_block.state.block_public_policy,
      aws_s3_bucket_public_access_block.state.ignore_public_acls,
      aws_s3_bucket_public_access_block.state.restrict_public_buckets,
    ])
    error_message = "Tout accès public au bucket de l'état doit être bloqué."
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.state.policy).Statement[0].Condition.Bool["aws:SecureTransport"] == "false" && jsondecode(aws_s3_bucket_policy.state.policy).Statement[0].Effect == "Deny"
    error_message = "Les accès hors HTTPS doivent être refusés."
  }

  assert {
    condition     = aws_s3_bucket_logging.state.target_prefix == "state-access/"
    error_message = "Les accès à l'état doivent être journalisés."
  }
}

run "journaux_proteges" {
  command = apply

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.logs.block_public_acls,
      aws_s3_bucket_public_access_block.logs.block_public_policy,
      aws_s3_bucket_public_access_block.logs.ignore_public_acls,
      aws_s3_bucket_public_access_block.logs.restrict_public_buckets,
    ])
    error_message = "Tout accès public au bucket des journaux doit être bloqué."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.logs.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    error_message = "Les journaux doivent être chiffrés (SSE-S3, seul mode accepté pour les journaux d'accès)."
  }
}
