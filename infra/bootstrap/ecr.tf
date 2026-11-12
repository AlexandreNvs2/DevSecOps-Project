# Dépôt d'images Docker de l'application.
#
# Placé dans le module bootstrap (permanent) et non avec l'infrastructure
# applicative, détruite en fin de session : les images publiées par la
# pipeline sont conservées.

resource "aws_ecr_repository" "app" {
  name = "password-checker"

  # Une image publiée ne peut pas être remplacée sous le même tag : le tag
  # (SHA du commit) désigne toujours exactement l'image testée en CI.
  image_tag_mutability = "IMMUTABLE"

  # Analyse des vulnérabilités à chaque envoi, en complément de Trivy.
  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
  }
}

# Seules les 20 dernières images sont conservées.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Conserver les 20 dernieres images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}
