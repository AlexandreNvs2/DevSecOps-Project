variable "region" {
  description = "Région AWS (le Learner Lab n'autorise que us-east-1)."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Préfixe des noms de ressources."
  type        = string
  default     = "password-checker"
}

variable "image_tag" {
  description = "Tag de l'image à déployer (SHA du commit, poussé dans ECR par la pipeline)."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{7,40}$", var.image_tag))
    error_message = "Le tag doit être un SHA de commit (tags immuables, jamais « latest »)."
  }
}

variable "availability_zones" {
  description = "Zones de disponibilité, fixées explicitement : l'infrastructure ne change pas si AWS ajoute une zone."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "Exactement deux zones (haute disponibilité de l'ALB, d'ECS et du groupe de sous-réseaux RDS)."
  }
}

variable "vpc_cidr" {
  description = "Plage d'adresses du VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "desired_count" {
  description = "Nombre de tâches ECS (réparties sur les zones)."
  type        = number
  default     = 2
}

variable "db_instance_class" {
  description = "Classe de l'instance RDS (petites classes uniquement dans le lab)."
  type        = string
  default     = "db.t3.micro"
}

variable "login_rate_limit" {
  description = "Requêtes maximales vers /login par adresse IP sur 5 minutes (WAF)."
  type        = number
  default     = 100
}

variable "log_retention_days" {
  description = "Durée de conservation des journaux CloudWatch."
  type        = number
  default     = 365
}
