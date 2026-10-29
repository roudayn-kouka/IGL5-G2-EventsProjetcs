resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

resource "random_password" "grafana" {
  length  = 20
  special = false
}

resource "kubernetes_secret" "grafana_admin" {
  metadata {
    name      = "grafana-admin"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
  data = {
    "admin-user"     = "admin"
    "admin-password" = random_password.grafana.result
  }
}

resource "helm_release" "monitoring" {
  name       = "monitoring"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "65.5.1"
  timeout    = 900
  wait       = true

  values     = [file("${path.module}/kube-prometheus-values.yaml")]
  depends_on = [kubernetes_secret.grafana_admin]
}