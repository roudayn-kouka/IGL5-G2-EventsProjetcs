variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/config"
}

variable "grafana_host" {
  type    = string
  default = "grafana.apps.local"
}

variable "grafana_admin_password" {
  type      = string
  sensitive = true
}