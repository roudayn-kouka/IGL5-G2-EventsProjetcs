terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 5.70" }
    helm       = { source = "hashicorp/helm", version = "~> 2.15" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.33" }
    local      = { source = "hashicorp/local", version = "~> 2.5" }
  }

  # État partagé de l'équipe (recommandé) : créer le bucket et la table une fois, puis décommenter.
  # backend "s3" {
  #   bucket         = "fst-events-tfstate"
  #   key            = "platform/terraform.tfstate"
  #   region         = "eu-west-3"
  #   dynamodb_table = "fst-events-tflock"
  #   encrypt        = true
  # }
}
