# =============================================================================
#  terraform test : choix du cluster EKS selon le compte, sans identifiants AWS.
#  Fournisseurs simulés (mock_provider) : aucun appel réseau, aucune ressource.
#    cd platform/terraform && terraform init -backend=false && terraform test
# =============================================================================

# Valeurs simulées communes, valides pour les validations du fournisseur AWS
mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b"] }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012", arn = "arn:aws:sts::123456789012:assumed-role/admin/user" }
  }
  mock_data "aws_iam_session_context" {
    defaults = { issuer_arn = "arn:aws:iam::123456789012:role/admin" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_eks_addon_version" {
    defaults = { version = "v1.0.0-eksbuild.1" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mock" }
  }
  mock_resource "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::123456789012:policy/mock" }
  }
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::123456789012:oidc-provider/mock" }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-1:123456789012:key/mock" }
  }
  mock_resource "aws_launch_template" {
    defaults = { id = "lt-0123456789abcdef0", latest_version = 1 }
  }
  mock_resource "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:us-east-1:123456789012:cluster/fst-events"
      certificate_authority = [{ data = "Y2E=" }]
      identity              = [{ oidc = [{ issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/MOCK" }] }]
    }
  }
}

# AWS Academy : même simulation, mais l'identité appelante a un ARN invalide.
# Le module EKS la transmet à data.aws_iam_session_context (iam:GetRole sur voclabs,
# refusé sur le lab) : si cette lecture avait lieu, la validation d'ARN ferait échouer
# le scénario. Il passe donc seulement si aucun contexte de session IAM n'est lu.
mock_provider "aws" {
  alias = "academy"

  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b"] }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012", arn = "lecture-interdite-sur-aws-academy" }
  }
  mock_resource "aws_launch_template" {
    defaults = { id = "lt-0123456789abcdef0", latest_version = 1 }
  }
  mock_resource "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:us-east-1:123456789012:cluster/fst-events"
      certificate_authority = [{ data = "Y2E=" }]
      identity              = [{ oidc = [{ issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/MOCK" }] }]
    }
  }
}

mock_provider "kubernetes" {}
mock_provider "helm" {}
mock_provider "local" {}
mock_provider "tls" {}
mock_provider "time" {}
mock_provider "cloudinit" {}
mock_provider "null" {}

variables {
  admin_cidr             = "198.51.100.10/32"
  grafana_admin_password = "test"
  ssh_public_key_path    = "tests/fixtures/id_ed25519.pub"
}

run "compte_classique_utilise_le_module" {
  variables {
    region       = "eu-west-3"
    lab_role_arn = ""
  }

  assert {
    condition     = length(module.eks) == 1
    error_message = "Le compte classique doit utiliser le module EKS."
  }
  assert {
    condition     = length(aws_eks_cluster.lab) == 0 && length(aws_eks_node_group.lab) == 0 && length(aws_launch_template.lab_nodes) == 0 && length(aws_eks_addon.lab_network) == 0 && length(aws_eks_addon.lab_workloads) == 0
    error_message = "Aucune ressource EKS native ne doit exister en compte classique."
  }
  assert {
    condition     = output.eks_cluster_name == module.eks[0].cluster_name
    error_message = "Les locals doivent pointer sur le module en compte classique."
  }
  assert {
    condition     = module.eks[0].cluster_iam_role_name != null && module.eks[0].oidc_provider_arn != null && length(aws_iam_role.devops) == 1
    error_message = "Le compte classique garde ses rôles IAM et IRSA."
  }
}

run "academy_sans_iam_ni_module" {
  providers = {
    aws        = aws.academy
    kubernetes = kubernetes
    helm       = helm
    local      = local
    tls        = tls
    time       = time
    cloudinit  = cloudinit
    null       = null
  }

  variables {
    region               = "us-east-1"
    lab_role_arn         = "arn:aws:iam::123456789012:role/LabRole"
    devops_instance_type = "t3.large"
    node_instance_type   = "t3.large"
    cluster_version      = "1.34"
  }

  # Aucun module EKS : ni aws_iam_session_context, ni rôle, politique, OIDC ou clé KMS du module
  assert {
    condition     = length(module.eks) == 0
    error_message = "Le module EKS ne doit pas être instancié sur AWS Academy."
  }
  # Aucune ressource aws_iam_* hors module (les seules sont celles de l'EC2 DevOps)
  assert {
    condition     = length(aws_iam_role.devops) == 0 && length(aws_iam_role_policy.devops_ecr) == 0 && length(aws_iam_instance_profile.devops) == 0
    error_message = "Aucune ressource aws_iam_* ne doit être créée sur AWS Academy."
  }
  assert {
    condition     = aws_instance.devops.iam_instance_profile == "LabInstanceProfile"
    error_message = "L'EC2 DevOps doit utiliser LabInstanceProfile."
  }

  # Cluster natif : LabRole, accès admin donné par EKS au créateur, sans KMS
  assert {
    condition     = aws_eks_cluster.lab[0].role_arn == var.lab_role_arn && aws_eks_cluster.lab[0].name == "fst-events" && aws_eks_cluster.lab[0].version == "1.34"
    error_message = "Cluster natif : nom, version ou LabRole incorrects."
  }
  assert {
    condition     = length(aws_eks_cluster.lab[0].encryption_config) == 0
    error_message = "Aucun chiffrement KMS ne doit être configuré sur AWS Academy."
  }
  assert {
    condition     = aws_eks_cluster.lab[0].access_config[0].authentication_mode == "API_AND_CONFIG_MAP" && aws_eks_cluster.lab[0].access_config[0].bootstrap_cluster_creator_admin_permissions
    error_message = "L'accès admin du créateur doit être donné par EKS (access_config)."
  }
  assert {
    condition     = aws_eks_cluster.lab[0].vpc_config[0].endpoint_private_access && aws_eks_cluster.lab[0].vpc_config[0].endpoint_public_access && one(aws_eks_cluster.lab[0].vpc_config[0].public_access_cidrs) == var.admin_cidr
    error_message = "Endpoints privé et public attendus, public limité à admin_cidr."
  }

  # Nœuds : LabRole, AL2023, 2/2/4, IMDSv2 avec 2 sauts
  assert {
    condition     = aws_eks_node_group.lab[0].node_role_arn == var.lab_role_arn && aws_eks_node_group.lab[0].ami_type == "AL2023_x86_64_STANDARD" && one(aws_eks_node_group.lab[0].instance_types) == "t3.large"
    error_message = "Groupe de nœuds : LabRole, AL2023 et t3.large attendus."
  }
  assert {
    condition     = aws_eks_node_group.lab[0].scaling_config[0].min_size == 2 && aws_eks_node_group.lab[0].scaling_config[0].desired_size == 2 && aws_eks_node_group.lab[0].scaling_config[0].max_size == 4
    error_message = "Taille du groupe de nœuds attendue : 2 / 2 / 4."
  }
  assert {
    condition     = aws_eks_node_group.lab[0].launch_template[0].id == aws_launch_template.lab_nodes[0].id && aws_launch_template.lab_nodes[0].metadata_options[0].http_tokens == "required" && aws_launch_template.lab_nodes[0].metadata_options[0].http_put_response_hop_limit == 2
    error_message = "Launch template : IMDSv2 obligatoire et 2 sauts."
  }
  assert {
    condition     = toset(keys(aws_eks_addon.lab_network)) == toset(["vpc-cni", "kube-proxy"]) && toset(keys(aws_eks_addon.lab_workloads)) == toset(["coredns", "aws-ebs-csi-driver"])
    error_message = "Modules complémentaires attendus : vpc-cni, kube-proxy, coredns, aws-ebs-csi-driver."
  }

  # Les fournisseurs Kubernetes/Helm, les outputs et Ansible suivent le cluster natif
  assert {
    condition     = output.eks_cluster_name == aws_eks_cluster.lab[0].name && local.cluster_endpoint == aws_eks_cluster.lab[0].endpoint && local.cluster_ca == "Y2E="
    error_message = "Les locals doivent pointer sur le cluster natif sur AWS Academy."
  }
}
