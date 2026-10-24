locals {
  use_lab_role = var.lab_role_arn != ""
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = var.project
  cluster_version = var.cluster_version

  cluster_endpoint_public_access           = true
  cluster_endpoint_public_access_cidrs     = [var.admin_cidr]
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # AWS Academy : réutiliser LabRole au lieu de créer des rôles IAM
  create_iam_role = !local.use_lab_role
  iam_role_arn    = local.use_lab_role ? var.lab_role_arn : null

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
