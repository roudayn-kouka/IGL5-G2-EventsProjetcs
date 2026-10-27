# Registre d'images : les nœuds EKS tirent les images grâce à leur rôle IAM (pas de secret de registre)
resource "aws_ecr_repository" "events_app" {
  name                 = "events-app"
  image_tag_mutability = "IMMUTABLE" # un tag = une version, impossible à écraser
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true # deuxième scan de vulnérabilités, côté AWS
  }
}

resource "aws_ecr_lifecycle_policy" "events_app" {
  repository = aws_ecr_repository.events_app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Conserver les 50 images les plus récentes"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 50 }
      action       = { type = "expire" }
    }]
  })
}
