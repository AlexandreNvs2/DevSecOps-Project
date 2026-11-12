# Groupes de sécurité : chaque niveau n'accepte que le niveau précédent.
#
# Descriptions sans accent ni apostrophe : AWS n'accepte que les caractères
# a-zA-Z0-9. _-:/()#,@[]+=&;{}!$* (vérifié par le test « descriptions_aws »).
#   Internet --443/80--> ALB --8080--> ECS --5432--> RDS

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "ALB : HTTPS et HTTP (redirection) depuis Internet"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS depuis Internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  #checkov:skip=CKV_AWS_260:Port 80 ouvert uniquement pour rediriger vers HTTPS (réponse 301 de l'ALB, aucune requête transmise à l'application) ; prouvé par le test « entree_https ».
  security_group_id = aws_security_group.alb.id
  description       = "HTTP depuis Internet, redirige vers HTTPS"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Vers les taches ECS uniquement"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = local.container_port
  to_port                      = local.container_port
}

resource "aws_security_group" "app" {
  name        = "${var.name}-app"
  description = "Taches ECS : trafic depuis le load balancer uniquement"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "Depuis le load balancer uniquement"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = local.container_port
  to_port                      = local.container_port
}

# Sortie HTTPS : récupération de l'image (ECR), des secrets (Secrets
# Manager), envoi des journaux (CloudWatch), via le NAT.
resource "aws_vpc_security_group_egress_rule" "app_https" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS vers les API AWS (ECR, Secrets Manager, CloudWatch)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "app_to_db" {
  security_group_id            = aws_security_group.app.id
  description                  = "Vers la base PostgreSQL uniquement"
  referenced_security_group_id = aws_security_group.db.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_security_group" "db" {
  name        = "${var.name}-db"
  description = "RDS : PostgreSQL depuis les taches ECS uniquement"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL depuis les taches ECS uniquement"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}
