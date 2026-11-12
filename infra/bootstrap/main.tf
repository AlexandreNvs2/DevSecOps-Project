# Stockage distant et sécurisé de l'état Terraform.
#
# L'état décrit toute l'infrastructure et peut contenir des secrets
# (SECRET_KEY générée, clé privée du certificat auto-signé). Il est donc :
# - chiffré avec une clé KMS dédiée, avec rotation annuelle ;
# - versionné (retour arrière possible après une erreur ou une corruption) ;
# - inaccessible publiquement et uniquement en HTTPS ;
# - journalisé (accès tracés dans un bucket de journaux séparé) ;
# - protégé contre la suppression accidentelle (prevent_destroy).

data "aws_caller_identity" "current" {}

locals {
  # Le numéro de compte rend le nom unique au niveau mondial, sans
  # l'écrire dans le dépôt.
  account_id  = data.aws_caller_identity.current.account_id
  state_name  = "devsecops-tfstate-${local.account_id}"
  logs_name   = "devsecops-tfstate-logs-${local.account_id}"
  account_arn = "arn:aws:iam::${local.account_id}:root"
}

# ---------------------------------------------------------------------------
# Clé KMS dédiée à l'état
# ---------------------------------------------------------------------------
resource "aws_kms_key" "state" {
  description             = "Chiffrement de l'etat Terraform"
  enable_key_rotation     = true
  deletion_window_in_days = 30

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
# Bucket de l'état
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "state" {
  #checkov:skip=CKV_AWS_144:Réplication inter-régions impossible : elle exige un rôle IAM dédié, que le Learner Lab interdit de créer, et le lab est limité à us-east-1. Le versioning couvre la restauration (test bootstrap.tftest.hcl).
  #checkov:skip=CKV2_AWS_62:Pas de notification d'événements : aucun consommateur. Chaque modification reste traçable par le versioning et les journaux d'accès.
  bucket = local.state_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.state]
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

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
  bucket        = aws_s3_bucket.state.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "state-access/"
}

# ---------------------------------------------------------------------------
# Bucket des journaux d'accès
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "logs" {
  #checkov:skip=CKV_AWS_18:Bucket de journaux : il ne peut pas journaliser ses propres accès (boucle infinie).
  #checkov:skip=CKV_AWS_144:Réplication inter-régions impossible (pas de création de rôle IAM dans le Learner Lab, région unique).
  #checkov:skip=CKV2_AWS_62:Pas de notification d'événements : aucun consommateur.
  #checkov:skip=CKV_AWS_145:Les journaux d'accès S3 ne peuvent être livrés que dans un bucket chiffré en SSE-S3 (AES-256), pas en SSE-KMS (exigence AWS).
  bucket = local.logs_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Autorise uniquement le service de journalisation S3, pour le bucket de
# l'état de ce compte, à écrire les journaux ; refuse tout accès hors HTTPS.
resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "S3ServerAccessLogs"
        Effect    = "Allow"
        Principal = { Service = "logging.s3.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.logs.arn}/state-access/*"
        Condition = {
          ArnLike      = { "aws:SourceArn" = aws_s3_bucket.state.arn }
          StringEquals = { "aws:SourceAccount" = local.account_id }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.logs.arn, "${aws_s3_bucket.logs.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.logs]
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

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
