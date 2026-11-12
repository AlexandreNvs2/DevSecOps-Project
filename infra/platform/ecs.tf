# Application : ECS Fargate, conteneurs sans serveur à gérer.

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.app.arn
}

resource "aws_ecs_cluster" "main" {
  name = var.name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_task_definition" "app" {
  #checkov:skip=CKV_AWS_249:Rôle d'exécution et rôle de tâche identiques (LabRole) : le Learner Lab interdit de créer des rôles IAM. En production, deux rôles distincts limités au strict nécessaire.
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512

  execution_role_arn = data.aws_iam_role.lab.arn
  task_role_arn      = data.aws_iam_role.lab.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = "app"
    image     = local.image
    essential = true

    # Valeurs par défaut d'AWS écrites explicitement (hostPort, listes
    # vides) : sinon chaque plan recréerait la définition de tâche.
    portMappings = [{
      containerPort = local.container_port
      hostPort      = local.container_port
      protocol      = "tcp"
    }]
    mountPoints    = []
    volumesFrom    = []
    systemControls = []

    # Durcissement, comme dans les tests du conteneur : système de fichiers
    # en lecture seule, aucune capacité Linux, utilisateur non root
    # (défini dans l'image), processus init pour les signaux.
    readonlyRootFilesystem = true
    user                   = "10001:10001"
    linuxParameters = {
      capabilities       = { add = [], drop = ["ALL"] }
      initProcessEnabled = true
    }

    environment = [
      { name = "DB_HOST", value = aws_db_instance.main.address },
      { name = "DB_PORT", value = tostring(aws_db_instance.main.port) },
      { name = "DB_NAME", value = aws_db_instance.main.db_name },
      { name = "DB_USER", value = aws_db_instance.main.username },
    ]

    # Secrets lus dans Secrets Manager par ECS au démarrage, jamais écrits
    # dans la définition de tâche.
    secrets = [
      { name = "SECRET_KEY", valueFrom = aws_secretsmanager_secret.secret_key.arn },
      { name = "DB_PASSWORD", valueFrom = "${aws_db_instance.main.master_user_secret[0].secret_arn}:password::" },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.app.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "app"
      }
    }
  }])
}

resource "aws_ecs_service" "app" {
  name            = var.name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  # Une tâche par zone de disponibilité.
  network_configuration {
    subnets          = aws_subnet.app[*].id
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = local.container_port
  }

  health_check_grace_period_seconds = 60

  # Un déploiement qui échoue est annulé automatiquement : la version
  # précédente reste en service.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  propagate_tags          = "SERVICE"
  enable_ecs_managed_tags = true

  depends_on = [aws_lb_listener.https]
}
