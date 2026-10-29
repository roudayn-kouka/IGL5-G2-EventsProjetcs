
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Reference the existing EKS cluster
data "aws_eks_cluster" "events" {
  name = "fst-events-eks"
}

# Manage untagged ECR images to reduce storage usage
resource "aws_ecr_lifecycle_policy" "events" {
  repository = "events-app"

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only one untagged image"
        selection = {
          tagStatus   = "untagged"
          countType   = "imageCountMoreThan"
          countNumber = 1
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

output "eks_cluster_name" {
  value = data.aws_eks_cluster.events.id
}
