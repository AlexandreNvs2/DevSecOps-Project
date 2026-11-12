output "url" {
  description = "Adresse publique de l'application (certificat auto-signé)."
  value       = "https://${aws_lb.main.dns_name}"
}

output "ecs_cluster" {
  value = aws_ecs_cluster.main.name
}

output "ecs_service" {
  value = aws_ecs_service.app.name
}
