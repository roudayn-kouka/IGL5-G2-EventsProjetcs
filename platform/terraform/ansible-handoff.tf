# =============================================================================
#  Passage de relais Terraform -> Ansible : inventaire + variables générés
# =============================================================================
resource "local_file" "ansible_inventory" {
  count           = var.enable_devops_ec2 ? 1 : 0
  filename        = "${path.module}/../ansible/inventory/hosts.ini"
  file_permission = "0644"
  content = templatefile("${path.module}/templates/hosts.ini.tftpl", {
    devops_ip = aws_eip.devops[0].public_ip
  })
}

resource "local_file" "ansible_tf_vars" {
  count           = var.enable_devops_ec2 ? 1 : 0
  filename        = "${path.module}/../ansible/group_vars/devops/terraform.yml"
  file_permission = "0644"
  content = templatefile("${path.module}/templates/terraform.yml.tftpl", {
    aws_region   = var.region
    ecr_registry = split("/", aws_ecr_repository.events_app.repository_url)[0]
    cluster_name = module.eks.cluster_name
    devops_ip    = aws_eip.devops[0].public_ip
  })
}
