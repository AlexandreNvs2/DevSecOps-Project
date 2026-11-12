# Stockage distant et sécurisé de l'état Terraform.
#
# L'état décrit toute l'infrastructure et peut contenir des secrets
# (SECRET_KEY générée, clé privée du certificat auto-signé). Il est donc :
# - chiffré avec une clé KMS dédiée, avec rotation annuelle ;
# - versionné (retour arrière possible après une erreur ou une corruption) ;
# - inaccessible publiquement et uniquement en HTTPS ;
# - journalisé (accès tracés dans un bucket de journaux séparé) ;
# - protégé contre la suppression accidentelle.
#
# Les deux buckets sont créés par create-buckets.sh et non par une ressource
# aws_s3_bucket : après chaque création ou lecture, le fournisseur AWS lit la
# configuration Object Lock du bucket (s3:GetBucketObjectLockConfiguration),
# action refusée explicitement par une SCP du Learner Lab. Terraform gère en
# revanche toute la configuration de sécurité des buckets ci-dessous, et ne
# peut pas les supprimer (protection contre un « terraform destroy »).

data "aws_caller_identity" "current" {}

locals {
  # Le numéro de compte rend le nom unique au niveau mondial, sans
  # l'écrire dans le dépôt.
  account_id  = data.aws_caller_identity.current.account_id
  state_name  = "devsecops-tfstate-${local.account_id}"
  logs_name   = "devsecops-tfstate-logs-${local.account_id}"
  state_arn   = "arn:aws:s3:::${local.state_name}"
  logs_arn    = "arn:aws:s3:::${local.logs_name}"
  account_arn = "arn:aws:iam::${local.account_id}:root"
}

# ---------------------------------------------------------------------------
# Clé KMS dédiée à l'état
# ---------------------------------------------------------------------------
resource "aws_kms_key" "state" {
  description             = "Chiffrement de l'etat Terraform"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  # Supprimer cette clé rendrait l'état illisible.
  lifecycle {
    prevent_destroy = true
  }

  # Politique explicite : seul le compte (donc ses identités IAM autorisées)
  # peut utiliser la clé.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AccountAdministration"
      Effect    = "Allow"
      Principal = { AWS = local.account_arn }
      Action    = "kms:*"
      Resource  = "*"
    }]
  })
}

resource "aws_kms_alias" "state" {
  name          = "alias/devsecops-tfstate"
  target_key_id = aws_kms_key.state.key_id
}

# ---------------------------------------------------------------------------
# Configuration du bucket de l'état
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "state" {
  bucket = local.state_name
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = local.state_name
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = local.state_name
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = local.state_name
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = local.state_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [local.state_arn, "${local.state_arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.state]
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = local.state_name

  rule {
    id     = "anciennes-versions"
    status = "Enabled"
    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

resource "aws_s3_bucket_logging" "state" {
  bucket        = local.state_name
  target_bucket = local.logs_name
  target_prefix = "state-access/"
}

# ---------------------------------------------------------------------------
# Configuration du bucket des journaux d'accès
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "logs" {
  bucket = local.logs_name
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = local.logs_name
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = local.logs_name
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = local.logs_name
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Autorise uniquement le service de journalisation S3, pour le bucket de
# l'état de ce compte, à écrire les journaux ; refuse tout accès hors HTTPS.
resource "aws_s3_bucket_policy" "logs" {
  bucket = local.logs_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "S3ServerAccessLogs"
        Effect    = "Allow"
        Principal = { Service = "logging.s3.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${local.logs_arn}/state-access/*"
        Condition = {
          ArnLike      = { "aws:SourceArn" = local.state_arn }
          StringEquals = { "aws:SourceAccount" = local.account_id }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [local.logs_arn, "${local.logs_arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.logs]
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = local.logs_name

  rule {
    id     = "expiration-journaux"
    status = "Enabled"
    filter {}

    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.logs]
}
