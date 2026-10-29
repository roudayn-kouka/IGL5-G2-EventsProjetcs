# =============================================================================
#  Amorçage GitOps : Terraform installe UNIQUEMENT Argo CD + l'application racine.
#  Tout le reste (ingress, monitoring, environnements Events) est déployé par Argo CD
#  depuis platform/gitops/ de la branche main (modèle « app of apps »).
# =============================================================================

resource "kubernetes_namespace" "monitoring" {
  metadata { name = "monitoring" }
  depends_on = [module.eks]
}

# Secrets consommés par la plateforme (jamais commités dans Git)
resource "kubernetes_secret" "grafana_admin" {
  metadata {
    name      = "grafana-admin"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
  data = {
    "admin-user"     = "admin"
    "admin-password" = var.grafana_admin_password
  }
}

resource "kubernetes_secret" "alertmanager_slack" {
  metadata {
    name      = "alertmanager-slack"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
  data = {
    "webhook-url" = var.slack_webhook_url
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "9.1.7" # Argo CD 3.2, tested with Kubernetes 1.34
  namespace        = "argocd"
  create_namespace = true

  values = [templatefile("${path.module}/values/argocd.yaml.tftpl", {
    platform_repo_url      = var.platform_repo_url
    github_token           = var.github_token
    slack_bot_token        = var.slack_bot_token
    internal_load_balancer = var.argocd_internal_load_balancer
    vpc_cidr               = module.vpc.vpc_cidr_block
  })]

  depends_on = [module.eks]
}

# Application racine : Argo CD se gère lui-même à partir de platform/gitops/platform/apps sur main.
resource "helm_release" "argocd_root" {
  name       = "argocd-root"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = "2.0.2"
  namespace  = "argocd"

  values = [yamlencode({
    applications = {
      platform = {
        namespace = "argocd"
        project   = "default"
        source = {
          repoURL        = var.platform_repo_url
          targetRevision = var.gitops_revision
          path           = "platform/gitops/platform/apps"
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "argocd"
        }
        syncPolicy = {
          automated = { prune = true, selfHeal = true }
        }
      }
    }
  })]

  depends_on = [helm_release.argocd, kubernetes_secret.grafana_admin, kubernetes_secret.alertmanager_slack]
}
