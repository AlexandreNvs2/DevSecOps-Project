terraform {
  # 1.10 minimum : verrouillage natif de l'état dans S3 (use_lockfile).
  required_version = "~> 1.17"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73"
    }
  }

  # Pas de backend distant ici : ce module crée justement le bucket qui
  # stockera l'état des autres modules (problème de l'œuf et de la poule).
  # Son propre état, local, ne contient aucun secret.
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "devsecops-project"
      ManagedBy = "terraform"
      Module    = "bootstrap"
    }
  }
}
