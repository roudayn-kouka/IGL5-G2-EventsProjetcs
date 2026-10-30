provider "aws" {
  region = var.region
  default_tags {
    tags = {
      project    = var.project
      team       = "igl5-g2"
      managed-by = "terraform"
    }
  }
}

# Accès au cluster EKS créé dans ce même code (jeton IAM temporaire, aucun kubeconfig stocké)
locals {
  eks_exec = {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.eks_cluster_name, "--region", var.region]
  }
}

provider "kubernetes" {
  host                   = local.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(local.eks_cluster_ca)
  exec {
    api_version = local.eks_exec.api_version
    command     = local.eks_exec.command
    args        = local.eks_exec.args
  }
}

provider "helm" {
  kubernetes {
    host                   = local.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(local.eks_cluster_ca)
    exec {
      api_version = local.eks_exec.api_version
      command     = local.eks_exec.command
      args        = local.eks_exec.args
    }
  }
}
