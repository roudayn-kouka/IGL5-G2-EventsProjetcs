# =============================================================================
#  AWS Academy (lab_role_arn non vide) : EKS en ressources natives.
#  Le module terraform-aws-modules/eks lit toujours data.aws_iam_session_context,
#  donc iam:GetRole sur le rôle de session voclabs, refusé par la politique du lab.
#  Ici : aucun appel IAM, aucune ressource IAM, pas de KMS ni d'OIDC; LabRole
#  sert de rôle au cluster et aux nœuds.
# =============================================================================

resource "aws_eks_cluster" "lab" {
  count = local.use_lab_role ? 1 : 0

  name     = var.project
  version  = var.cluster_version
  role_arn = var.lab_role_arn

  vpc_config {
    subnet_ids              = module.vpc.private_subnets
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = [var.admin_cidr]
  }

  # EKS donne lui-même l'accès administrateur au créateur (rôle voclabs), sans appel IAM
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
}

# Nœuds : IMDSv2 obligatoire, 2 sauts pour que les pods (pilote EBS CSI) atteignent
# les identifiants du rôle du nœud (LabRole), faute d'IRSA.
resource "aws_launch_template" "lab_nodes" {
  count = local.use_lab_role ? 1 : 0

  name_prefix = "${var.project}-nodes-"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.project}-node" }
  }
}

resource "aws_eks_node_group" "lab" {
  count = local.use_lab_role ? 1 : 0

  cluster_name    = aws_eks_cluster.lab[0].name
  node_group_name = "workers"
  node_role_arn   = var.lab_role_arn
  subnet_ids      = module.vpc.private_subnets
  instance_types  = [var.node_instance_type]
  ami_type        = "AL2023_x86_64_STANDARD" # plus d'AMI AL2 à partir de Kubernetes 1.33

  scaling_config {
    min_size     = 2
    desired_size = 2
    max_size     = 4
  }

  launch_template {
    id      = aws_launch_template.lab_nodes[0].id
    version = aws_launch_template.lab_nodes[0].latest_version
  }

  # L'autoscaling peut changer le nombre de nœuds sans que Terraform le réinitialise
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [aws_eks_addon.lab_network]
}

# Réseau des pods : avant les nœuds, sinon ils restent NotReady
resource "aws_eks_addon" "lab_network" {
  for_each = local.use_lab_role ? toset(["vpc-cni", "kube-proxy"]) : toset([])

  cluster_name                = aws_eks_cluster.lab[0].name
  addon_name                  = each.key
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# Ces modules complémentaires ont besoin de nœuds pour démarrer
resource "aws_eks_addon" "lab_workloads" {
  for_each = local.use_lab_role ? toset(["coredns", "aws-ebs-csi-driver"]) : toset([])

  cluster_name                = aws_eks_cluster.lab[0].name
  addon_name                  = each.key
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.lab]
}
