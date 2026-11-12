#!/usr/bin/env bash
# Crée les buckets S3 du projet, avant « terraform apply » :
# - devsecops-tfstate-<compte>      : état Terraform ;
# - devsecops-tfstate-logs-<compte> : journaux d'accès à l'état ;
# - devsecops-logs-<compte>         : journaux de l'ALB et du VPC.
#
# Pourquoi un script et pas une ressource aws_s3_bucket : le fournisseur
# Terraform AWS lit la configuration Object Lock de chaque bucket qu'il gère
# (s3:GetBucketObjectLockConfiguration), action refusée par une SCP du
# Learner Lab. Le script ne fait que créer les buckets ; toute leur
# configuration de sécurité (KMS, versioning, politique HTTPS, journaux,
# cycle de vie) est appliquée ensuite par Terraform (main.tf).
#
# Idempotent : un bucket déjà présent dans le compte n'est pas recréé.
# Un nouveau bucket S3 a par défaut l'accès public bloqué, les ACL
# désactivées et un chiffrement SSE-S3.
set -euo pipefail

region="${AWS_REGION:-us-east-1}"
account="$(aws sts get-caller-identity --query Account --output text)"

for name in "devsecops-tfstate-${account}" "devsecops-tfstate-logs-${account}" \
  "devsecops-logs-${account}"; do
  if aws s3api head-bucket --bucket "$name" --expected-bucket-owner "$account" 2>/dev/null; then
    echo "Déjà présent : $name"
  else
    # us-east-1 n'accepte pas de LocationConstraint.
    if [ "$region" = "us-east-1" ]; then
      aws s3api create-bucket --bucket "$name" --region "$region" >/dev/null
    else
      aws s3api create-bucket --bucket "$name" --region "$region" \
        --create-bucket-configuration "LocationConstraint=$region" >/dev/null
    fi
    echo "Créé : $name"
  fi
done
