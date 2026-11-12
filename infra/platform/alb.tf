# Application Load Balancer : seul point d'entrée depuis Internet.

resource "aws_lb" "main" {
  #checkov:skip=CKV_AWS_150:Protection contre la suppression désactivée : l'infrastructure est détruite en fin de session (budget du lab). L'ALB ne contient aucune donnée et Terraform le recrée à l'identique. En production, activée.
  name               = var.name
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  # En-têtes HTTP invalides supprimés avant d'atteindre l'application
  # (protection contre la dissimulation de requêtes, request smuggling).
  drop_invalid_header_fields = true
  desync_mitigation_mode     = "strictest"

  enable_deletion_protection = false

  access_logs {
    enabled = true
    bucket  = local.logs_bucket
    prefix  = "alb"
  }
}

# Certificat auto-signé (aucun nom de domaine dans le lab), émis pour le
# nom DNS de l'ALB et importé dans ACM. Le navigateur affiche un
# avertissement ; en production : certificat ACM validé par DNS.
resource "tls_private_key" "alb" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "alb" {
  private_key_pem = tls_private_key.alb.private_key_pem

  subject {
    common_name  = aws_lb.main.dns_name
    organization = "DevSecOps-Project"
  }
  dns_names = [aws_lb.main.dns_name]

  validity_period_hours = 24 * 90
  early_renewal_hours   = 24 * 15

  allowed_uses = ["digital_signature", "key_encipherment", "server_auth"]
}

resource "aws_acm_certificate" "alb" {
  private_key      = tls_private_key.alb.private_key_pem
  certificate_body = tls_self_signed_cert.alb.cert_pem

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "app" {
  name        = var.name
  port        = local.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  deregistration_delay = 30

  health_check {
    path                = "/"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# HTTPS : TLS 1.2 minimum, TLS 1.3 privilégié.
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.alb.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# HTTP : redirection permanente vers HTTPS, rien n'est transmis à
# l'application en clair.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
