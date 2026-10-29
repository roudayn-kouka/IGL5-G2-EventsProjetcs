# Exercise the REAL patched module, not an override_module. Every run is plan-only
# with mocked providers: no IAM, EKS, KMS or persisted state operations occur.
mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com", reverse_dns_prefix = "com.amazonaws" }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:sts::123456789012:assumed-role/voclabs/mock-session"
    }
  }
  mock_data "aws_iam_session_context" {
    defaults = { issuer_arn = "arn:aws:iam::123456789012:role/voclabs" }
  }
}
mock_provider "tls" {}
mock_provider "time" {}
mock_provider "cloudinit" {}
mock_provider "null" {}

run "academy_explicit_admin_without_role_lookup" {
  command = plan
  module { source = "./modules/eks-academy" }
  variables {
    cluster_name                             = "fst-events"
    cluster_version                          = "1.34"
    vpc_id                                   = "vpc-0123456789abcdef0"
    subnet_ids                               = ["subnet-11111111", "subnet-22222222"]
    cluster_endpoint_public_access_cidrs     = ["192.0.2.1/32"]
    enable_cluster_creator_admin_permissions = false
    create_iam_role                          = false
    iam_role_arn                             = "arn:aws:iam::123456789012:role/LabRole"
    enable_irsa                              = false
    create_kms_key                           = false
    cluster_encryption_config                = {}
    access_entries = {
      academy_admin = {
        principal_arn = "arn:aws:iam::123456789012:role/voclabs"
        type          = "STANDARD"
        policy_associations = {
          admin = {
            policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = { type = "cluster" }
          }
        }
      }
    }
  }
  assert {
    condition     = length(data.aws_iam_session_context.current) == 0
    error_message = "Academy must not perform the denied source-role lookup."
  }
  assert {
    condition     = aws_eks_access_entry.this["academy_admin"].principal_arn == "arn:aws:iam::123456789012:role/voclabs" && aws_eks_access_entry.this["academy_admin"].type == "STANDARD"
    error_message = "Preserve admin access for the actual kubectl principal."
  }
  assert {
    condition     = aws_eks_access_policy_association.this["academy_admin_admin"].policy_arn == "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" && aws_eks_access_policy_association.this["academy_admin_admin"].access_scope[0].type == "cluster"
    error_message = "Admin access must retain its cluster-wide administrator association."
  }
  assert {
    condition     = length(aws_iam_role.this) == 0 && aws_eks_cluster.this[0].access_config[0].bootstrap_cluster_creator_admin_permissions == false && length(aws_eks_cluster.this[0].vpc_config[0].public_access_cidrs) == 1 && contains(aws_eks_cluster.this[0].vpc_config[0].public_access_cidrs, "192.0.2.1/32")
    error_message = "Preserve Academy IAM and API network restrictions."
  }
}

run "standard_automatic_creator_still_resolves_role" {
  command = plan
  module { source = "./modules/eks-academy" }
  variables {
    cluster_name                             = "standard-test"
    vpc_id                                   = "vpc-0123456789abcdef0"
    subnet_ids                               = ["subnet-11111111", "subnet-22222222"]
    enable_cluster_creator_admin_permissions = true
    create_iam_role                          = false
    iam_role_arn                             = "arn:aws:iam::123456789012:role/test"
    enable_irsa                              = false
    create_kms_key                           = false
    cluster_encryption_config                = {}
  }
  assert {
    condition     = length(data.aws_iam_session_context.current) == 1 && aws_eks_access_entry.this["cluster_creator"].principal_arn == "arn:aws:iam::123456789012:role/voclabs"
    error_message = "Non-Academy automatic creator access must remain functional."
  }
}
