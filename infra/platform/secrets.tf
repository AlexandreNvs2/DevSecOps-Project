# SECRET_KEY de Flask : générée par Terraform, stockée chiffrée dans
# Secrets Manager, injectée par ECS au démarrage du conteneur. Elle n'est
# jamais dans le dépôt ni dans l'image ; elle figure dans l'état Terraform,
# lui-même chiffré par KMS dans S3 (voir infra/bootstrap).
resource "random_password" "secret_key" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "secret_key" {
  #checkov:skip=CKV2_AWS_57:Pas de rotation automatique : elle exigerait une fonction Lambda dédiée, et changer la clé invalide toutes les sessions. La clé est régénérée à chaque recréation de l'infrastructure (destroy en fin de session).
  name        = "${var.name}/secret-key"
  description = "Cle secrete Flask (sessions et jetons CSRF)"
  kms_key_id  = aws_kms_key.app.arn

  # Suppression immédiate : l'infrastructure est détruite et recréée à
  # chaque session du lab, sous le même nom.
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "secret_key" {
  secret_id     = aws_secretsmanager_secret.secret_key.id
  secret_string = random_password.secret_key.result
}
