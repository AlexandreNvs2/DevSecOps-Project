# Base PostgreSQL : privée, chiffrée, connexions TLS obligatoires.
#
# Mot de passe généré et conservé par RDS dans Secrets Manager
# (manage_master_user_password) : Terraform ne le connaît jamais, il
# n'apparaît donc pas dans l'état.

resource "aws_db_subnet_group" "main" {
  name       = var.name
  subnet_ids = aws_subnet.db[*].id
}

resource "aws_db_parameter_group" "main" {
  name   = var.name
  family = "postgres18"

  # Refus de toute connexion non chiffrée. Paramètre statique : AWS le
  # marque « pending-reboot » (sans cette précision, chaque plan afficherait
  # une modification).
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  # Journalisation des changements de schéma et des requêtes lentes. Pas de
  # « all » : les paramètres des requêtes (identifiants, empreintes de mot
  # de passe) finiraient dans les journaux.
  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  # PostgreSQL 18 : log_connections n'est plus un booléen mais une liste
  # d'étapes (réception, authentification, autorisation).
  parameter {
    name  = "log_connections"
    value = "all"
  }
}

resource "aws_db_instance" "main" {
  #checkov:skip=CKV_AWS_157:Multi-AZ désactivé (budget du lab) ; en production, instance de secours dans une autre zone.
  #checkov:skip=CKV_AWS_118:Supervision avancée impossible : elle exige un rôle approuvé par monitoring.rds.amazonaws.com, que LabRole n'accepte pas et qu'il est interdit de créer. Performance Insights et les journaux PostgreSQL restent activés.
  #checkov:skip=CKV_AWS_293:Protection contre la suppression désactivée : l'infrastructure est détruite en fin de session (budget du lab). En production, activée.
  identifier     = var.name
  engine         = "postgres"
  engine_version = "18"
  instance_class = var.db_instance_class

  db_name  = "app"
  username = "app"

  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.app.key_id

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true
  kms_key_id        = aws_kms_key.app.arn

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  parameter_group_name   = aws_db_parameter_group.main.name

  iam_database_authentication_enabled = true
  auto_minor_version_upgrade          = true
  enabled_cloudwatch_logs_exports     = ["postgresql", "upgrade"]

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.app.arn
  performance_insights_retention_period = 7

  backup_retention_period = 7
  copy_tags_to_snapshot   = true

  # Destruction en fin de session : pas d'instantané final, pas de
  # protection contre la suppression (voir les exceptions ci-dessus).
  deletion_protection = false
  skip_final_snapshot = true
  apply_immediately   = true
}
