terraform {
  required_version = ">= 1.9"

  backend "local" {}

  required_providers {
    helm       = { source = "hashicorp/helm", version = "~> 2.15" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.33" }
    random     = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}