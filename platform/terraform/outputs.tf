output "devops_public_ip" {
  description = "IP élastique de l'usine DevOps"
  value       = one(aws_eip.devops[*].public_ip)
}

output "devops_urls" {
  value = var.create_devops_ec2 ? {
    jenkins   = "https://jenkins.${aws_eip.devops[0].public_ip}.sslip.io"
    sonarqube = "https://sonar.${aws_eip.devops[0].public_ip}.sslip.io"
    nexus     = "https://nexus.${aws_eip.devops[0].public_ip}.sslip.io"
  } : {}
}

output "ecr_repository_url" {
  value = aws_ecr_repository.events_app.repository_url
}

output "eks_cluster_name" {
  value = local.eks_cluster_name
}

output "region" {
  description = "Région AWS de l'infrastructure (contrôlée par post-apply.sh et destroy.sh)"
  value       = var.region
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${local.eks_cluster_name} --region ${var.region}"
}

output "next_steps" {
  value = <<-EOT
    1. cd ../ansible && ansible-galaxy collection install -r requirements.yml
    2. ansible-playbook site.yml --ask-vault-pass
    3. Argo CD : kubectl -n argocd port-forward svc/argocd-server 8080:80
       (mot de passe : kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
  EOT
}
