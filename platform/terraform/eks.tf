locals {
  use_lab_role = var.lab_role_arn != ""

  # Cluster effectif : module (compte classique) ou ressources natives (AWS Academy, eks-lab.tf)
  cluster_name     = local.use_lab_role ? one(aws_eks_cluster.lab[*].name) : one(module.eks[*].cluster_name)
  cluster_endpoint = local.use_lab_role ? one(aws_eks_cluster.lab[*].endpoint) : one(module.eks[*].cluster_endpoint)
  cluster_ca       = local.use_lab_role ? one(aws_eks_cluster.lab[*].certificate_authority[0].data) : one(module.eks[*].cluster_certificate_authority_data)
}

# Compte classique uniquement. Le module lit toujours data.aws_iam_session_context
# (iam:GetRole sur le rôle de session), refusé sur AWS Academy : voir eks-lab.tf.
module "eks" {
  count = local.use_lab_role ? 0 : 1

  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = var.project
  cluster_version = var.cluster_version

  cluster_endpoint_private_access          = true
  cluster_endpoint_public_access           = true
  cluster_endpoint_public_access_cidrs     = [var.admin_cidr]
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # AWS Academy : réutiliser LabRole au lieu de créer des rôles IAM, et pas de
  # fournisseur OIDC IAM (IRSA). Aucun pod n'utilise IRSA : le pilote EBS CSI
  # s'appuie sur le rôle des nœuds dans les deux modes.
  create_iam_role = !local.use_lab_role
  iam_role_arn    = local.use_lab_role ? var.lab_role_arn : null
  enable_irsa     = !local.use_lab_role

  cluster_addons = {
    coredns            = {}
    kube-proxy         = {}
    vpc-cni            = {}
    aws-ebs-csi-driver = {} # volumes EBS pour MySQL en staging / prod
  }

  eks_managed_node_groups = {
    workers = {
      instance_types = [var.node_instance_type]
      min_size       = 2
      desired_size   = 2
      max_size       = 4

      create_iam_role = !local.use_lab_role
      iam_role_arn    = local.use_lab_role ? var.lab_role_arn : null
      # Lecture ECR (images) et pilote EBS
      iam_role_additional_policies = local.use_lab_role ? {} : {
        ecr = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
        ebs = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      }
    }
  }
}

# Le module est passé de « module.eks » à « module.eks[0] » avec count : sans ce bloc,
# un cluster classique déjà créé serait détruit puis recréé.
moved {
  from = module.eks
  to   = module.eks[0]
}
