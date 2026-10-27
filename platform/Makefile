.DEFAULT_GOAL := help
# Région : AWS_REGION (ou AWS_DEFAULT_REGION) si définie, sinon celle de la configuration
# AWS CLI (aws configure get region, us-east-1 sur AWS Academy), sinon eu-west-3.
# Exportée : scripts, aws et terraform utilisent tous la même. Elle doit égaler
# « region » de terraform/terraform.tfvars (contrôlé par post-apply.sh et destroy.sh).
ifndef AWS_REGION
AWS_REGION := $(or $(AWS_DEFAULT_REGION),$(shell aws configure get region 2>/dev/null),eu-west-3)
endif
export AWS_REGION

.PHONY: help bootstrap-state init plan apply kubeconfig configure post-apply argocd-ui argocd-token grafana-ui status destroy

help:
	@echo "Région AWS : $(AWS_REGION)"
	@echo "Cibles disponibles :"
	@awk -F ':|##' '/^[a-zA-Z0-9_-]+:.*##/ { printf "  %-18s %s\n", $$1, $$3 }' $(MAKEFILE_LIST)

bootstrap-state: ## Crée le bucket S3 chiffré/versionné et la table DynamoDB
	@echo "Initialisation du backend Terraform distant (AWS CLI requis)."
	@bash scripts/bootstrap-state.sh

init: ## Initialise Terraform avec terraform/backend.hcl
	@echo "Initialisation des fournisseurs, modules et backend S3."
	@cd terraform && terraform init -backend-config=backend.hcl

plan: ## Affiche le plan Terraform sans appliquer de changements
	@echo "Calcul du plan Terraform; aucune ressource ne sera modifiée."
	@cd terraform && terraform plan

apply: ## Applique le plan Terraform et crée les ressources AWS
	@echo "ATTENTION : cette commande crée/modifie des ressources AWS et peut engendrer des coûts."
	@cd terraform && terraform apply

kubeconfig: ## Configure kubectl pour le cluster EKS déclaré par Terraform
	@echo "Mise à jour du kubeconfig local pour le cluster EKS."
	@aws eks update-kubeconfig --name "$$(cd terraform && terraform output -raw eks_cluster_name)" --region "$(AWS_REGION)"

configure: ## Configure Jenkins, Nexus et SonarQube via Ansible
	@echo "Installation des collections Ansible et exécution du playbook (Vault requis)."
	@cd ansible && ansible-galaxy collection install -r requirements.yml
	@cd ansible && ansible-playbook site.yml --ask-vault-pass

post-apply: ## Découvre les adresses des NLB, met à jour runtime.yml et commite les hôtes sur gitops
	@echo "Découverte des NLB, mise à jour du runtime Ansible et commit local des hôtes sur gitops."
	@bash scripts/post-apply.sh

argocd-ui: ## Ouvre l'interface Argo CD en port-forward sur localhost:8080
	@echo "Port-forward local vers l'API Argo CD (Ctrl+C pour arrêter)."
	@kubectl -n argocd port-forward svc/argocd-server 8080:80

argocd-token: ## Affiche la commande pour générer le jeton du compte Jenkins
	@echo "Après connexion administrateur à Argo CD, générez un jeton pour l'étape 13 :"
	@echo "argocd account generate-token --account jenkins --server localhost:8080 --grpc-web --plaintext"

grafana-ui: ## Ouvre Grafana en port-forward sur localhost:3000
	@echo "Port-forward local vers Grafana (Ctrl+C pour arrêter)."
	@kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80

status: ## Affiche les Applications Argo CD, les pods et les URL Terraform
	@echo "Applications Argo CD :"
	@kubectl -n argocd get applications
	@echo "Pods des namespaces Events et de la plateforme :"
	@kubectl get pods -A
	@echo "URL des outils (outputs Terraform) :"
	@cd terraform && terraform output devops_urls

destroy: ## Supprime l'infrastructure après nettoyage Kubernetes et confirmation
	@echo "Nettoyage ordonné des ressources Kubernetes puis confirmation avant Terraform destroy."
	@bash scripts/destroy.sh
