# Bucket des journaux de l'infrastructure applicative :
# - journaux d'accès de l'Application Load Balancer (préfixe alb/) ;
# - journaux de flux du VPC (préfixe vpc-flow-logs/).
#
# Créé par create-buckets.sh (voir main.tf). Permanent : les journaux
# survivent à la destruction de l'infrastructure en fin de session.

locals {
  app_logs_name = "devsecops-logs-${local.account_id}"
  app_logs_arn  = "arn:aws:s3:::${local.app_logs_name}"
}

# Compte AWS du service Elastic Load Balancing dans la région, autorisé à
# écrire les journaux de l'ALB (méthode imposée en us-east-1).
data "aws_elb_service_account" "current" {}

resource "aws_s3_bucket_versioning" "app_logs" {
  bucket = local.app_logs_name
  versioning_configuration {
    status = "Enabled"
  }
}

# L'ALB ne livre ses journaux que dans un bucket chiffré en SSE-S3.
resource "aws_s3_bucket_server_side_encryption_configuration" "app_logs" {
  bucket = local.app_logs_name
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "app_logs" {
  bucket                  = local.app_logs_name
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "app_logs" {
  bucket = local.app_logs_name
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_policy" "app_logs" {
  bucket = local.app_logs_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AlbAccessLogs"
        Effect    = "Allow"
        Principal = { AWS = data.aws_elb_service_account.current.arn }
        Action    = "s3:PutObject"
        Resource  = "${local.app_logs_arn}/alb/AWSLogs/${local.account_id}/*"
      },
      {
        Sid       = "VpcFlowLogsWrite"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${local.app_logs_arn}/vpc-flow-logs/AWSLogs/${local.account_id}/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
            "s3:x-amz-acl"      = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid       = "VpcFlowLogsAclCheck"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = local.app_logs_arn
        Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [local.app_logs_arn, "${local.app_logs_arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.app_logs]
}

resource "aws_s3_bucket_lifecycle_configuration" "app_logs" {
  bucket = local.app_logs_name

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

  depends_on = [aws_s3_bucket_versioning.app_logs]
}

# Les accès au bucket des journaux sont eux-mêmes journalisés, dans le
# bucket des journaux d'accès à l'état.
resource "aws_s3_bucket_logging" "app_logs" {
  bucket        = local.app_logs_name
  target_bucket = local.logs_name
  target_prefix = "app-logs-access/"
}
