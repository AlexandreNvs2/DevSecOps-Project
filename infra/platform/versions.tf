terraform {
  required_version = "~> 1.17"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.4"
    }
  }

  # État stocké dans le bucket créé par infra/bootstrap : chiffré par KMS,
  # versionné, verrouillé pendant chaque opération (use_lockfile).
  # Le nom du bucket (qui contient le numéro de compte) est passé à
  # l'initialisation : terraform init -backend-config="bucket=…".
  backend "s3" {
    key          = "platform/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    kms_key_id   = "alias/devsecops-tfstate"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "devsecops-project"
      ManagedBy = "terraform"
      Module    = "platform"
    }
  }
}
