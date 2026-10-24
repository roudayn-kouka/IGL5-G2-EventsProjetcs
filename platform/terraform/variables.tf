variable "project" {
  description = "Préfixe des ressources"
  type        = string
  default     = "fst-events"
}

variable "region" {
  description = "Région AWS (Paris)"
  type        = string
  default     = "eu-west-3"
}

variable "cluster_version" {
  type    = string
  default = "1.31"
}

variable "node_instance_type" {
  description = "Nœuds EKS"
  type        = string
  default     = "t3.large"
}

variable "devops_instance_type" {
  description = "EC2 « usine DevOps » (Jenkins, Nexus, SonarQube)"
  type        = string
  default     = "t3.xlarge"
}

variable "admin_cidr" {
  description = "CIDR autorisé en SSH sur l'usine DevOps et pour l'API publique EKS (ex. 196.203.10.20/32)"
  type        = string
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

variable "platform_repo_url" {
  description = "Dépôt GitOps surveillé par Argo CD"
  type        = string
  default     = "https://github.com/roudayn-kouka/IGL5-G2-Events-Platform.git"
}

variable "github_token" {
  description = "Jeton GitHub en lecture (seulement si le dépôt plateforme est privé)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "slack_bot_token" {
  description = "Jeton du bot Slack pour Argo CD Notifications"
  type        = string
  default     = ""
  sensitive   = true
}

variable "slack_webhook_url" {
  description = "Webhook Slack entrant pour Alertmanager"
  type        = string
  default     = ""
  sensitive   = true
}

variable "grafana_admin_password" {
  type      = string
  sensitive = true
}

variable "lab_role_arn" {
  description = "Compte AWS Academy : ARN de « LabRole » (aucun rôle IAM ne peut être créé). Laisser vide sinon."
  type        = string
  default     = ""
}
