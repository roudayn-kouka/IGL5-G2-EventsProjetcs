# Plan-only mocks: no AWS calls, no real resources, no persisted deployment state.
mock_provider "aws" {}
mock_provider "kubernetes" {}
mock_provider "helm" {}
mock_provider "local" {}

override_data {
  target = data.aws_caller_identity.academy_admin[0]
  values = {
    account_id = "123456789012"
    arn        = "arn:aws:sts::123456789012:assumed-role/voclabs/mock-session"
  }
}

override_module {
  target = module.vpc
  outputs = {
    vpc_id          = "vpc-0123456789abcdef0"
    vpc_cidr_block  = "10.20.0.0/16"
    public_subnets  = ["subnet-11111111", "subnet-22222222"]
    private_subnets = ["subnet-33333333", "subnet-44444444"]
  }
}
override_module {
  target = module.eks
  outputs = {
    cluster_name                       = "fst-events"
    cluster_endpoint                   = "https://example.invalid"
    cluster_certificate_authority_data = "dGVzdA=="
  }
}
override_resource {
  target = aws_ecr_repository.events_app
  values = { repository_url = "123456789012.dkr.ecr.us-east-1.amazonaws.com/events-app" }
}
variables {
  region                 = "us-east-1"
  admin_cidr             = "192.0.2.1/32"
  lab_role_arn           = "arn:aws:iam::123456789012:role/LabRole"
  grafana_admin_password = "mock-only-not-a-real-secret"
}
run "academy_local_toolchain" {
  command = plan
  variables {
    enable_devops_ec2 = false
    # Missing key must never be evaluated with EC2 disabled.
    ssh_public_key_path = "this-key-does-not-exist.pub"
  }
  assert {
    condition     = length(aws_instance.devops) == 0 && length(aws_eip.devops) == 0 && length(aws_key_pair.devops) == 0
    error_message = "Disabled toolchain must create no host, EIP or SSH key."
  }
  assert {
    condition     = length(local_file.ansible_inventory) == 0 && length(local_file.ansible_tf_vars) == 0
    error_message = "Disabled toolchain must not overwrite Ansible files."
  }
  assert {
    condition     = length(aws_iam_role.devops) == 0 && length(aws_iam_instance_profile.devops) == 0 && length(aws_iam_role_policy.devops_ecr) == 0
    error_message = "Academy must not create custom toolchain IAM resources."
  }
  assert {
    condition     = output.devops_public_ip == null && length(output.devops_urls) == 0
    error_message = "Disabled toolchain outputs must be safe."
  }
  assert {
    condition     = strcontains(helm_release.argocd.values[0], "type: ClusterIP")
    error_message = "Local Jenkins must not require an Argo load balancer."
  }
  assert {
    condition     = yamldecode(helm_release.argocd.values[0]).server.service.type == "ClusterIP"
    error_message = "Terraform-rendered Argo values must be valid YAML with private service access."
  }
}
run "academy_optional_host" {
  command = plan
  variables {
    enable_devops_ec2   = true
    ssh_public_key_path = "tests/mock-key.pub"
    devops_ami_id       = "ami-0123456789abcdef0"
  }
  assert {
    condition     = length(aws_instance.devops) == 1 && aws_instance.devops[0].iam_instance_profile == "LabInstanceProfile"
    error_message = "Optional Academy host must use the existing LabInstanceProfile."
  }
  assert {
    condition     = length(aws_iam_role.devops) == 0 && length(aws_iam_instance_profile.devops) == 0
    error_message = "Optional Academy host must not create IAM roles/profiles."
  }
}
run "standard_optional_host" {
  command = plan
  variables {
    lab_role_arn                  = ""
    enable_devops_ec2             = true
    argocd_internal_load_balancer = true
    ssh_public_key_path           = "tests/mock-key.pub"
    devops_ami_id                 = "ami-0123456789abcdef0"
  }
  assert {
    condition     = length(aws_iam_role.devops) == 1 && length(aws_iam_instance_profile.devops) == 1 && length(aws_instance.devops) == 1
    error_message = "Non-Academy toolchain must retain IAM provisioning."
  }
  assert {
    condition     = strcontains(helm_release.argocd.values[0], "aws-load-balancer-internal: \"true\"")
    error_message = "Optional Argo load balancer must stay internal."
  }
}
