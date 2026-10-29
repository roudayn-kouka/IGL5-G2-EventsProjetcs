terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 5.70" }
    helm       = { source = "hashicorp/helm", version = "~> 2.15" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.33" }
    local      = { source = "hashicorp/local", version = "~> 2.5" }
  }

  backend "s3" {}
}
