locals {
  use_lab_role = var.lab_role_arn != ""
}

data "aws_caller_identity" "academy_admin" {
  count = local.use_lab_role ? 1 : 0
  # GetCallerIdentity is enough; do not request iam:GetRole on voclabs.
  lifecycle {
    postcondition {
      condition = (
        can(regex("^arn:aws:sts::[0-9]{12}:assumed-role/voclabs/", self.arn)) &&
        var.lab_role_arn == "arn:aws:iam::${self.account_id}:role/LabRole"
      )
      error_message = "Academy admin access expects the existing voclabs session and LabRole in the same account. Review access explicitly if the principal changes."
    }
  }
}

module "eks" {
  # Upstream v20.37.2, with one documented conditional data-lookup patch.
  source = "./modules/eks-academy"

  cluster_name    = var.project
  cluster_version = var.cluster_version

  cluster_endpoint_private_access          = true
  cluster_endpoint_public_access           = true
  cluster_endpoint_public_access_cidrs     = [var.admin_cidr]
  enable_cluster_creator_admin_permissions = !local.use_lab_role
  access_entries = local.use_lab_role ? {
    academy_admin = {
      # kubectl/Helm use voclabs credentials, not the EKS/node service LabRole.
      principal_arn = "arn:aws:iam::${data.aws_caller_identity.academy_admin[0].account_id}:role/voclabs"
      type          = "STANDARD"
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  } : {}

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  # The targeted bootstrap must include NAT/routes before private workers start.
  depends_on = [module.vpc]

  # AWS Academy : réutiliser LabRole au lieu de créer des rôles IAM, et pas de
  # fournisseur OIDC IAM (IRSA). Aucun pod n'utilise IRSA : le pilote EBS CSI
  # s'appuie sur le rôle des nœuds dans les deux modes.
  create_iam_role = !local.use_lab_role
  iam_role_arn    = local.use_lab_role ? var.lab_role_arn : null
  enable_irsa     = !local.use_lab_role
  # Academy cannot create a KMS key policy granting newly created IAM roles.
  create_kms_key            = !local.use_lab_role
  cluster_encryption_config = local.use_lab_role ? {} : { resources = ["secrets"] }
  cluster_upgrade_policy    = { support_type = "STANDARD" }

  cluster_addons = {
    coredns            = { addon_version = lookup(var.addon_versions, "coredns", null) }
    kube-proxy         = { addon_version = lookup(var.addon_versions, "kube-proxy", null) }
    vpc-cni            = { before_compute = true, addon_version = lookup(var.addon_versions, "vpc-cni", null) }
    aws-ebs-csi-driver = { addon_version = lookup(var.addon_versions, "aws-ebs-csi-driver", null) }
    metrics-server     = { addon_version = lookup(var.addon_versions, "metrics-server", null) }
  }

  eks_managed_node_groups = {
    workers = {
      instance_types = [var.node_instance_type]
      ami_type       = "AL2023_x86_64_STANDARD"
      min_size       = var.worker_count
      desired_size   = var.worker_count
      max_size       = var.worker_count
      disk_size      = 20
      block_device_mappings = {
        root = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 20
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }
      # CSI uses the node role in Academy; allow IMDSv2 from pods.
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 2
      }

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
