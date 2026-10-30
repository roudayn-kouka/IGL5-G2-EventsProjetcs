# =============================================================================
#  Amorçage GitOps : Terraform installe UNIQUEMENT Argo CD + l'application racine.
#  Tout le reste (ingress, monitoring, environnements Events) est déployé par Argo CD
#  depuis platform/gitops/ de la branche main (modèle « app of apps »).
# =============================================================================

resource "kubernetes_namespace" "monitoring" {
  metadata { name = "monitoring" }
  depends_on = [module.eks, aws_eks_node_group.lab]
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
  version          = "7.7.11"
  namespace        = "argocd"
  create_namespace = true

  values = [templatefile("${path.module}/values/argocd.yaml.tftpl", {
    platform_repo_url = var.platform_repo_url
    github_token      = var.github_token
    slack_bot_token   = var.slack_bot_token
    devops_cidr       = var.create_devops_ec2 ? "${aws_eip.devops[0].public_ip}/32" : ""
    argocd_public     = var.argocd_public
    admin_cidr        = var.admin_cidr
    vpc_cidr          = module.vpc.vpc_cidr_block
  })]

  depends_on = [module.eks, aws_eks_node_group.lab]
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
        source = merge({
          repoURL        = var.platform_repo_url
          targetRevision = "main"
          path           = "platform/gitops/platform/apps"
          },
          # appset_only_env : l'ApplicationSet (40-...) est appliqué par Jenkins avec un seul environnement
          var.appset_only_env == "" ? {} : { directory = { exclude = "40-events-environments.yaml" } }
        )
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
