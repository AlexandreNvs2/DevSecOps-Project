# Clé KMS de l'application : chiffre la base, ses sauvegardes, les secrets
# et les journaux CloudWatch.

resource "aws_kms_key" "app" {
  description             = "Chiffrement des donnees de ${var.name}"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        # Les tâches ECS (rôle LabRole) déchiffrent les secrets au démarrage.
        Sid       = "EcsDecryptSecrets"
        Effect    = "Allow"
        Principal = { AWS = data.aws_iam_role.lab.arn }
        Action    = ["kms:Decrypt", "kms:DescribeKey"]
        Resource  = "*"
      },
      {
        # CloudWatch Logs chiffre les groupes de journaux de ce compte.
        Sid       = "CloudWatchLogs"
        Effect    = "Allow"
        Principal = { Service = "logs.${var.region}.amazonaws.com" }
        Action = [
          "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*",
          "kms:GenerateDataKey*", "kms:DescribeKey",
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.region}:${local.account_id}:log-group:*"
          }
        }
      },
    ]
  })
}

resource "aws_kms_alias" "app" {
  name          = "alias/${var.name}"
  target_key_id = aws_kms_key.app.key_id
}
