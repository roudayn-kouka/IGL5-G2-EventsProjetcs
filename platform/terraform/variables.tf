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
  default = "1.34"
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
  validation {
    condition     = can(cidrnetmask(var.admin_cidr)) && endswith(var.admin_cidr, "/32")
    error_message = "Use your actual public IPv4 /32; do not open the EKS API to the world."
  }
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

variable "platform_repo_url" {
  description = "URL HTTPS du dépôt applicatif unique (application et plateforme)"
  type        = string
  default     = "https://github.com/roudayn-kouka/IGL5-G2-EventsProjetcs.git"
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
  validation {
    condition     = length(var.grafana_admin_password) >= 16 && var.grafana_admin_password != "change-me"
    error_message = "Supply a unique Grafana password of at least 16 characters through TF_VAR_grafana_admin_password."
  }
}

variable "lab_role_arn" {
  description = "Compte AWS Academy : ARN de « LabRole » (aucun rôle IAM ne peut être créé). Laisser vide sinon."
  type        = string
  default     = ""
  validation {
    condition     = var.lab_role_arn == "" || can(regex("^arn:aws:iam::[0-9]{12}:role/LabRole$", var.lab_role_arn))
    error_message = "Supply the real LabRole ARN, or leave empty for a non-Academy deployment."
  }
}

variable "enable_devops_ec2" {
  description = "Provision the optional EC2 toolchain; disable when Jenkins/Nexus/SonarQube run locally."
  type        = bool
  default     = true
}

variable "devops_ami_id" {
  description = "Optional pinned Ubuntu AMI ID for repeatable EC2 plans."
  type        = string
  default     = null
}

variable "worker_count" {
  description = "Fixed worker capacity (no cluster autoscaler is installed)."
  type        = number
  default     = 2
  validation {
    condition     = var.worker_count >= 2 && var.worker_count <= 4 && floor(var.worker_count) == var.worker_count
    error_message = "Use between two and four workers."
  }
}

variable "argocd_internal_load_balancer" {
  description = "Internal-only NLB for VPC Jenkins; false uses ClusterIP and an authenticated port-forward."
  type        = bool
  default     = false
}

variable "gitops_revision" {
  description = "Reviewed branch or commit containing platform manifests/chart; gitops remains the runtime values branch."
  type        = string
  default     = "main"
}

variable "ecr_force_delete" {
  description = "Allow deleting repository images during an explicitly confirmed demo teardown."
  type        = bool
  default     = false
}

variable "addon_versions" {
  description = "Optional pinned addon versions verified for the selected Kubernetes version."
  type        = map(string)
  default     = {}
}
