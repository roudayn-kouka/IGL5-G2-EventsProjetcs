output "devops_public_ip" {
  description = "IP élastique de l'usine DevOps"
  value       = try(aws_eip.devops[0].public_ip, null)
}

output "devops_urls" {
  value = var.enable_devops_ec2 ? {
    jenkins   = "https://jenkins.${aws_eip.devops[0].public_ip}.sslip.io"
    sonarqube = "https://sonar.${aws_eip.devops[0].public_ip}.sslip.io"
    nexus     = "https://nexus.${aws_eip.devops[0].public_ip}.sslip.io"
  } : {}
}

output "ecr_repository_url" {
  value = aws_ecr_repository.events_app.repository_url
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "region" {
  description = "Région AWS de l'infrastructure (contrôlée par post-apply.sh et destroy.sh)"
  value       = var.region
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "ecr_registry" {
  value = split("/", aws_ecr_repository.events_app.repository_url)[0]
}

output "next_steps" {
  value = var.enable_devops_ec2 ? "Configure the optional EC2 with Ansible, then follow docs/ACADEMY-DEMO.md." : "Use local Jenkins and the private port-forward procedure in docs/ACADEMY-DEMO.md."
}
