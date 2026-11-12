# Tests du module platform, sans compte AWS : fournisseur AWS simulé
# (mock_provider), « apply » ne crée rien et calcule des valeurs factices.
# Les fournisseurs tls et random s'exécutent réellement (calcul local).
#
# Ils prouvent les garanties de sécurité de l'architecture, notamment
# celles qui justifient les exceptions Checkov (voir le README).
#
# Lancement : terraform init -backend=false && terraform test

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/LabRole"
    }
  }

  mock_data "aws_ecr_repository" {
    defaults = {
      repository_url = "123456789012.dkr.ecr.us-east-1.amazonaws.com/password-checker"
    }
  }

  # Le fournisseur valide le format des ARN : valeurs factices réalistes.
  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    }
  }

  mock_resource "aws_acm_certificate" {
    defaults = {
      arn = "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
    }
  }

  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/password-checker/0123456789abcdef"
    }
  }

  mock_resource "aws_wafv2_web_acl" {
    defaults = {
      arn = "arn:aws:wafv2:us-east-1:123456789012:regional/webacl/password-checker/00000000-0000-0000-0000-000000000000"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:mock"
    }
  }

  mock_resource "aws_secretsmanager_secret" {
    defaults = {
      arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:password-checker/secret-key-AbCdEf"
    }
  }

  mock_resource "aws_lb" {
    defaults = {
      arn      = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/password-checker/0123456789abcdef"
      dns_name = "password-checker-123456789.us-east-1.elb.amazonaws.com"
    }
  }

  mock_resource "aws_db_instance" {
    defaults = {
      address = "password-checker.abcdefghij.us-east-1.rds.amazonaws.com"
      port    = 5432
      master_user_secret = [{
        secret_arn    = "arn:aws:secretsmanager:us-east-1:123456789012:secret:rds!db-0000-AbCdEf"
        kms_key_id    = "mock"
        secret_status = "active"
      }]
    }
  }
}

variables {
  image_tag = "0123456789abcdef0123456789abcdef01234567"
}

run "entree_https" {
  command = apply

  # Justifie CKV_AWS_260 : le port 80 ne fait que rediriger vers HTTPS.
  assert {
    condition = (
      aws_lb_listener.http.default_action[0].type == "redirect" &&
      aws_lb_listener.http.default_action[0].redirect[0].protocol == "HTTPS" &&
      aws_lb_listener.http.default_action[0].redirect[0].status_code == "HTTP_301"
    )
    error_message = "Le port 80 doit uniquement rediriger vers HTTPS (aucun transfert vers l'application)."
  }

  assert {
    condition     = aws_lb_listener.https.protocol == "HTTPS" && startswith(aws_lb_listener.https.ssl_policy, "ELBSecurityPolicy-TLS13-1-2")
    error_message = "L'application doit être servie en HTTPS, TLS 1.2 minimum."
  }

  assert {
    condition     = aws_lb.main.drop_invalid_header_fields == true
    error_message = "Les en-têtes HTTP invalides doivent être supprimés."
  }

  assert {
    condition     = aws_lb.main.access_logs[0].enabled == true
    error_message = "Les accès à l'ALB doivent être journalisés."
  }

  assert {
    condition     = contains(tls_self_signed_cert.alb.dns_names, "password-checker-123456789.us-east-1.elb.amazonaws.com")
    error_message = "Le certificat doit être émis pour le nom DNS de l'ALB."
  }
}

run "cloisonnement_reseau" {
  command = apply

  assert {
    condition     = aws_vpc_security_group_ingress_rule.app_from_alb.referenced_security_group_id == aws_security_group.alb.id
    error_message = "Les tâches ECS ne doivent accepter que le trafic de l'ALB."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.db_from_app.referenced_security_group_id == aws_security_group.app.id
    error_message = "La base ne doit accepter que les tâches ECS."
  }

  assert {
    condition     = aws_ecs_service.app.network_configuration[0].assign_public_ip == false
    error_message = "Les tâches ECS ne doivent pas avoir d'adresse publique."
  }

  assert {
    condition     = length(aws_route_table.db.route) == 0
    error_message = "Les sous-réseaux de la base ne doivent avoir aucune route vers Internet."
  }

  assert {
    condition     = length(aws_default_security_group.default.ingress) == 0 && length(aws_default_security_group.default.egress) == 0
    error_message = "Le groupe de sécurité par défaut ne doit autoriser aucun trafic."
  }

  assert {
    condition     = aws_flow_log.vpc.traffic_type == "ALL"
    error_message = "Tout le trafic du VPC doit être journalisé."
  }
}

run "base_de_donnees" {
  command = apply

  assert {
    condition     = aws_db_instance.main.publicly_accessible == false
    error_message = "La base ne doit pas être accessible publiquement."
  }

  assert {
    condition     = aws_db_instance.main.storage_encrypted == true
    error_message = "La base doit être chiffrée."
  }

  assert {
    condition     = aws_db_instance.main.manage_master_user_password == true
    error_message = "Le mot de passe de la base doit être généré et stocké par AWS (jamais connu de Terraform)."
  }

  assert {
    condition     = one([for p in aws_db_parameter_group.main.parameter : p.value if p.name == "rds.force_ssl"]) == "1"
    error_message = "Les connexions non chiffrées à la base doivent être refusées."
  }

  assert {
    condition     = one([for p in aws_db_parameter_group.main.parameter : p.value if p.name == "log_statement"]) != "all"
    error_message = "Les paramètres des requêtes (données personnelles, empreintes) ne doivent pas être journalisés."
  }

  # Compense l'absence de supervision avancée (CKV_AWS_118).
  assert {
    condition     = aws_db_instance.main.performance_insights_enabled == true && contains(aws_db_instance.main.enabled_cloudwatch_logs_exports, "postgresql")
    error_message = "Performance Insights et les journaux PostgreSQL doivent être activés."
  }

  # Avec Multi-AZ désactivé (CKV_AWS_157), les sauvegardes permettent la restauration.
  assert {
    condition     = aws_db_instance.main.backup_retention_period >= 7
    error_message = "Les sauvegardes automatiques doivent être conservées au moins 7 jours."
  }
}

run "conteneurs_durcis" {
  command = apply

  assert {
    condition     = jsondecode(aws_ecs_task_definition.app.container_definitions)[0].readonlyRootFilesystem == true
    error_message = "Le système de fichiers du conteneur doit être en lecture seule."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.app.container_definitions)[0].linuxParameters.capabilities.drop == ["ALL"]
    error_message = "Toutes les capacités Linux doivent être retirées."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.app.container_definitions)[0].user == "10001:10001"
    error_message = "Le conteneur doit s'exécuter avec un utilisateur non root."
  }

  # Aucun secret en clair dans la définition de tâche : ils sont référencés.
  assert {
    condition     = alltrue([for e in jsondecode(aws_ecs_task_definition.app.container_definitions)[0].environment : !contains(["SECRET_KEY", "DB_PASSWORD", "DATABASE_URL"], e.name)])
    error_message = "Aucun secret ne doit être passé en variable d'environnement en clair."
  }

  assert {
    condition     = toset([for s in jsondecode(aws_ecs_task_definition.app.container_definitions)[0].secrets : s.name]) == toset(["SECRET_KEY", "DB_PASSWORD"])
    error_message = "SECRET_KEY et DB_PASSWORD doivent venir de Secrets Manager."
  }

  assert {
    condition     = endswith(jsondecode(aws_ecs_task_definition.app.container_definitions)[0].image, ":0123456789abcdef0123456789abcdef01234567")
    error_message = "L'image déployée doit être désignée par le SHA du commit."
  }

  assert {
    condition     = aws_ecs_service.app.deployment_circuit_breaker[0].rollback == true
    error_message = "Un déploiement en échec doit être annulé automatiquement."
  }
}

run "pare_feu_applicatif" {
  command = apply

  assert {
    condition     = one([for r in aws_wafv2_web_acl.main.rule : r if r.name == "limite-login"]).statement[0].rate_based_statement[0].scope_down_statement[0].byte_match_statement[0].search_string == "/login"
    error_message = "Le WAF doit limiter le débit des requêtes vers /login."
  }

  assert {
    condition     = one([for r in aws_wafv2_web_acl.main.rule : r if r.name == "limite-login"]).action[0].block != null
    error_message = "Les adresses dépassant la limite sur /login doivent être bloquées."
  }

  assert {
    condition     = contains([for r in aws_wafv2_web_acl.main.rule : r.name], "AWSManagedRulesKnownBadInputsRuleSet")
    error_message = "Les entrées malveillantes connues (Log4Shell) doivent être bloquées."
  }

  assert {
    condition     = aws_wafv2_web_acl_association.alb.resource_arn == aws_lb.main.arn
    error_message = "Le WAF doit protéger l'ALB."
  }
}

# Régression : AWS refuse à l'exécution (et non au plan) les descriptions de
# groupes de sécurité contenant une apostrophe ou un accent.
run "descriptions_aws" {
  command = apply

  assert {
    condition = alltrue([
      for d in concat(
        [aws_security_group.alb.description, aws_security_group.app.description, aws_security_group.db.description],
        [
          aws_vpc_security_group_ingress_rule.alb_https.description,
          aws_vpc_security_group_ingress_rule.alb_http.description,
          aws_vpc_security_group_egress_rule.alb_to_app.description,
          aws_vpc_security_group_ingress_rule.app_from_alb.description,
          aws_vpc_security_group_egress_rule.app_https.description,
          aws_vpc_security_group_egress_rule.app_to_db.description,
          aws_vpc_security_group_ingress_rule.db_from_app.description,
        ],
      ) : can(regex("^[a-zA-Z0-9. _:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", d))
    ])
    error_message = "Description de groupe de sécurité refusée par AWS (caractères autorisés : a-zA-Z0-9. _-:/()#,@[]+=&;{}!$*)."
  }
}

run "tag_image_invalide" {
  command = plan

  variables {
    image_tag = "latest"
  }

  expect_failures = [var.image_tag]
}
