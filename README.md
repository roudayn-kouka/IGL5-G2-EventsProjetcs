<h1 align="center">Events Project — Plateforme (IaC + GitOps)</h1>

<p align="center">
  Infrastructure AWS et déploiements de l'application <a href="https://github.com/roudayn-kouka/IGL5-G2-EventsProjetcs">Events</a><br>
  <b>Faculté des Sciences de Tunis</b> · IGL5 — Groupe 2
</p>

<p align="center"><img src="docs/architecture.png" alt="Architecture" width="950"></p>

## Rôle de ce dépôt

Deux dépôts, deux responsabilités :

| Dépôt | Contenu | Qui écrit dedans |
|---|---|---|
| **IGL5-G2-EventsProjetcs** (application) | Code Spring Boot, tests, `Jenkinsfile`, `Dockerfile` | L'équipe (Pull Requests GitFlow) |
| **IGL5-G2-Events-Platform** (ce dépôt) | Terraform, Ansible, chart Helm, manifests Argo CD, état voulu des environnements | L'équipe (infra) et **Jenkins** (`gitops/envs/`) |

Jenkins ne déploie jamais directement : il écrit le tag de la nouvelle image dans `gitops/envs/<env>/values.yaml`.
**Argo CD**, installé dans le cluster, détecte ce commit et met le cluster en conformité (modèle *pull*).

## Arborescence

```
terraform/          # AWS : VPC, EKS, ECR, EC2 « usine DevOps », IAM, Argo CD (amorçage)
ansible/            # Configuration de l'EC2 : Docker, Jenkins (JCasC), Nexus, SonarQube, Caddy
gitops/
├── charts/events-app/          # chart Helm de l'application (+ MySQL, ingress, ServiceMonitor, HPA)
├── envs/<env>/                 # un dossier = un environnement (écrit par Jenkins)
│   ├── config.json             #   namespace, profil, responsable
│   └── values.yaml             #   image + URL
└── platform/
    ├── apps/                   # « app of apps » Argo CD : projet, ingress, monitoring, ApplicationSet
    └── monitoring-config/      # règles d'alerte + dashboard Grafana
```

## Mise en place (une fois)

```bash
# 1. Infrastructure AWS
cd terraform
cp terraform.tfvars.example terraform.tfvars      # renseigner admin_cidr, secrets Slack, Grafana...
terraform init && terraform apply                 # ~20 min : VPC, EKS, ECR, EC2, Argo CD

# 2. Configuration de l'usine DevOps (l'inventaire a été généré par Terraform)
cd ../ansible
ansible-galaxy collection install -r requirements.yml
cp group_vars/devops/vault.yml.example group_vars/devops/vault.yml && ansible-vault encrypt group_vars/devops/vault.yml
ansible-playbook site.yml --ask-vault-pass

# 3. Jetons à créer une fois les outils démarrés, puis relancer le playbook
#    - Argo CD : compte « jenkins » + argocd account generate-token --account jenkins
#    - SonarQube : token utilisateur + webhook vers https://jenkins.<ip>.sslip.io/sonarqube-webhook/
#    - GitHub : webhook du dépôt application vers https://jenkins.<ip>.sslip.io/github-webhook/
```

## Flux de déploiement

1. Un membre pousse `feature/<nom>` → Jenkins (CI, sécurité, image dans ECR).
2. Jenkins écrit `gitops/envs/<nom>/` et pousse sur `main`.
3. L'ApplicationSet crée `events-<nom>`, et Argo CD synchronise le namespace `events-<nom>`.
4. Prometheus découvre l'application (ServiceMonitor). Grafana l'affiche, Alertmanager alerte sur Slack.

## Supprimer un environnement de feature

```bash
git rm -r gitops/envs/<nom> && git commit -m "cleanup(<nom>): feature fusionnée" && git push
```
Argo CD supprime l'application et toutes ses ressources (finalizer).

## Coûts

Environ 0,5 $ par heure quand tout tourne (ordre de grandeur, à vérifier sur la calculatrice AWS). Entre deux séances :
`terraform destroy`, ou réduire le nodegroup à 0 et arrêter l'EC2.
