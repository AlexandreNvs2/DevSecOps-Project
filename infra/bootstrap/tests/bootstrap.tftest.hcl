# Tests du module bootstrap, sans compte AWS : le fournisseur est simulé
# (mock_provider), « apply » ne crée rien et calcule des valeurs factices.
# Ils prouvent que les garanties de sécurité de l'état sont en place.
#
# Lancement : terraform init -backend=false && terraform test

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_elb_service_account" {
    defaults = {
      arn = "arn:aws:iam::127311923021:root"
    }
  }
}

run "etat_protege" {
  command = apply

  assert {
    condition     = aws_s3_bucket_versioning.state.bucket == "devsecops-tfstate-123456789012"
    error_message = "Le nom du bucket doit être dérivé du numéro de compte (aucune donnée du compte dans le dépôt)."
  }

  assert {
    condition     = aws_s3_bucket_ownership_controls.state.rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "Les ACL doivent être désactivées sur le bucket de l'état."
  }

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

  assert {
    condition     = contains(jsondecode(aws_s3_bucket_policy.logs.policy).Statement[0].Condition.ArnLike["aws:SourceArn"], "arn:aws:s3:::devsecops-tfstate-123456789012")
    error_message = "Seuls les journaux du bucket de l'état peuvent être écrits dans le bucket des journaux."
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.logs.policy).Statement[1].Effect == "Deny" && jsondecode(aws_s3_bucket_policy.logs.policy).Statement[1].Condition.Bool["aws:SecureTransport"] == "false"
    error_message = "Les accès hors HTTPS au bucket des journaux doivent être refusés."
  }
}

run "depot_images" {
  command = apply

  assert {
    condition     = aws_ecr_repository.app.image_tag_mutability == "IMMUTABLE"
    error_message = "Les tags d'image doivent être immuables."
  }

  assert {
    condition     = aws_ecr_repository.app.image_scanning_configuration[0].scan_on_push == true
    error_message = "Chaque image envoyée doit être analysée."
  }

  assert {
    condition     = aws_ecr_repository.app.encryption_configuration[0].encryption_type == "KMS"
    error_message = "Les images doivent être chiffrées avec KMS."
  }
}

run "journaux_application" {
  command = apply

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.app_logs.block_public_acls,
      aws_s3_bucket_public_access_block.app_logs.block_public_policy,
      aws_s3_bucket_public_access_block.app_logs.ignore_public_acls,
      aws_s3_bucket_public_access_block.app_logs.restrict_public_buckets,
    ])
    error_message = "Tout accès public au bucket des journaux applicatifs doit être bloqué."
  }

  assert {
    condition     = aws_s3_bucket_versioning.app_logs.versioning_configuration[0].status == "Enabled"
    error_message = "Les journaux doivent être versionnés (une suppression reste récupérable)."
  }

  assert {
    condition     = one([for st in jsondecode(aws_s3_bucket_policy.app_logs.policy).Statement : st if st.Sid == "DenyInsecureTransport"]).Effect == "Deny"
    error_message = "Les accès hors HTTPS au bucket des journaux applicatifs doivent être refusés."
  }

  assert {
    condition     = one([for st in jsondecode(aws_s3_bucket_policy.app_logs.policy).Statement : st if st.Sid == "AlbAccessLogs"]).Resource == "arn:aws:s3:::devsecops-logs-123456789012/alb/AWSLogs/123456789012/*"
    error_message = "L'ALB ne doit pouvoir écrire que sous son préfixe, pour ce compte."
  }

  assert {
    condition     = aws_s3_bucket_logging.app_logs.target_bucket == "devsecops-tfstate-logs-123456789012"
    error_message = "Les accès au bucket des journaux applicatifs doivent être journalisés."
  }
}
