# =============================================================================
#  Cluster EKS en ressources simples (eks_raw = true), pour les Learner Lab qui refusent iam:GetRole.
#  Le module communautaire terraform-aws-modules/eks appelle toujours data.aws_iam_session_context,
#  qui lit le rôle de la session (voclabs) : « explicit deny » sur certains comptes Academy.
#  Ici : cluster et nœuds utilisent LabRole, aucun appel IAM. Les add-ons de base (CoreDNS, kube-proxy, VPC CNI)
#  sont installés automatiquement par EKS ; le pilote EBS CSI n'est pas installé (inutile : base MySQL éphémère en review).
# =============================================================================
resource "aws_eks_cluster" "lab" {
  count    = var.eks_raw ? 1 : 0
  name     = var.project
  version  = var.cluster_version
  role_arn = var.lab_role_arn

  vpc_config {
    subnet_ids              = concat(module.vpc.private_subnets, module.vpc.public_subnets)
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = [var.admin_cidr]
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true # l'identité qui lance Terraform devient administrateur du cluster
  }

  lifecycle {
    precondition {
      condition     = var.lab_role_arn != ""
      error_message = "eks_raw = true exige lab_role_arn (ARN de LabRole)."
    }
  }
}

resource "aws_eks_node_group" "lab" {
  count           = var.eks_raw ? 1 : 0
  cluster_name    = aws_eks_cluster.lab[0].name
  node_group_name = "workers"
  node_role_arn   = var.lab_role_arn
  subnet_ids      = module.vpc.private_subnets
  ami_type        = "AL2023_x86_64_STANDARD"
  instance_types  = [var.node_instance_type]

  scaling_config {
    min_size     = 2
    desired_size = 2
    max_size     = 4
  }
}

# Adresse du cluster, quel que soit le mode (module ou ressources simples)
locals {
  eks_cluster_name     = var.eks_raw ? aws_eks_cluster.lab[0].name : module.eks[0].cluster_name
  eks_cluster_endpoint = var.eks_raw ? aws_eks_cluster.lab[0].endpoint : module.eks[0].cluster_endpoint
  eks_cluster_ca       = var.eks_raw ? aws_eks_cluster.lab[0].certificate_authority[0].data : module.eks[0].cluster_certificate_authority_data
}
