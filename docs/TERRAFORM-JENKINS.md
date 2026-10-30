# Terraform dans le pipeline Jenkins

## Objectif et périmètre

Le `Jenkinsfile` conserve la chaîne applicative existante : Maven, JUnit/JaCoCo,
SonarQube, Nexus, Docker, Trivy, ECR, promotion GitOps, Argo CD et smoke tests.
Terraform est un chemin **opt-in** pour remettre en place la
plateforme partagée EKS/ECR/Argo, pas une étape exécutée pour chaque changement
de code.

Le chemin Terraform est disponible pour un build direct de `develop` quand le
paramètre Jenkins `PROVISION_INFRASTRUCTURE` est coché. Une exception explicitement
limitée à `feature/feedback` existe pour la démonstration Academy approuvée. Les
PR, les autres branches `feature/*` et `main` le sautent. `main` conserve sa
propre approbation de promotion applicative et ne peut pas provisionner via ce
pipeline.

Ne cochez ce paramètre que lorsqu'un opérateur souhaite réellement restaurer ou
mettre à jour la plateforme. Les builds normaux doivent le laisser à `false`.

## Credentials Jenkins requis

Les credentials doivent être créés ou vérifiés dans le dossier/job Jenkins de
confiance qui exécute `develop`. Ils ne sont ni lus ni copiés dans Git.

| ID | Type Jenkins | Utilisation |
|---|---|---|
| `aws-academy-credentials` | **Secret file** | Profil `[default]` AWS Academy contenant access key, secret key et session token. Déjà utilisé par le push ECR. |
| `terraform-backend-config` | **Secret file** | Copie du `platform/terraform/backend.hcl` approuvé : bucket S3 existant, clé `platform/terraform.tfstate`, région, chiffrement et `use_lockfile=true`. Ce fichier ne contient pas de credentials. |
| `terraform-tfvars-academy` | **Secret file** | Valeurs non versionnées de `terraform.tfvars` pour AWS Academy : région, `admin_cidr`, ARN `LabRole`, versions d'addons, capacité et options existantes. |
| `grafana-admin-password` | **Secret text** | Valeur forte d'au moins 16 caractères injectée seulement comme `TF_VAR_grafana_admin_password`. |

Les credentials Nexus, SonarQube, GitHub et Argo CD existants restent utilisés par
leurs stages actuels. Le Jenkinsfile associe `aws-academy-credentials` à
`AWS_SHARED_CREDENTIALS_FILE`, désactive le traçage shell avant toute commande
AWS, vide les variables AWS héritées et vérifie `aws sts get-caller-identity`.
Une session Academy expirée échoue avant le plan : télécharger de nouvelles
credentials Academy, remplacer le Secret file Jenkins, puis relancer un nouveau
build. Ne collez jamais ces valeurs dans un paramètre de build ou un log.

## Déroulement d'un provisioning approuvé

1. Lancer `develop`, ou l'exception approuvée `feature/feedback`, avec
   `PROVISION_INFRASTRUCTURE=true` et `LOCAL_DEMO=false`.
2. Jenkins initialise le backend S3 déjà approuvé avec `-lockfile=readonly`, puis
   exécute `terraform fmt -check -recursive` et `terraform validate` depuis
   `platform/terraform`.
3. Il produit un plan de bootstrap enregistré qui cible seulement EKS et ECR. Le
   résumé sans valeurs sensibles est affiché dans la console et archivé.
4. Un opérateur Jenkins approuve ce plan. Jenkins applique exactement ce fichier
   de plan, avec le verrou S3 et un délai de verrouillage de cinq minutes.
5. Jenkins attend le cluster EKS actif, chaque node group actif, les nœuds
   Kubernetes `Ready` et le dépôt ECR disponible.
6. Il produit alors le plan complet Argo/monitoring, demande une seconde
   approbation, et applique exactement ce second plan.
7. La chaîne existante reprend : image Docker, ECR, GitOps, Argo CD et smoke
   tests. Le scan OWASP ZAP a été retiré à la demande du propriétaire du projet.

Deux plans sont nécessaires pour un compte sans EKS : les providers Kubernetes et
Helm du projet dépendent de l'endpoint et du jeton du cluster. Cette séparation
reprend le flux existant de `platform/scripts/academy.ps1`.

Si l'un des plans contient une action `delete` ou un remplacement (qui contient
une suppression), Jenkins échoue avant l'étape d'approbation. Examiner alors
l'état S3, les variables Academy et les changements Terraform : ne pas relancer
avec `apply` manuel ni supprimer le verrou.

## Sécurité, coûts et exploitation

- Aucun stage Jenkins ne lance `terraform destroy`.
- Les fichiers `.tfplan`, `terraform.tfvars`, `backend.hcl`, state et secrets sont
  ignorés par Git. Les plans binaires sont supprimés du workspace en fin de build;
  seuls les résumés sans secrets sont archivés.
- Le backend est réutilisé, sans migration automatique de bucket, de clé ou de
  state. Le verrou S3 natif n'est jamais contourné.
- Les stages Terraform utilisent l'agent local Jenkins doté de Terraform 1.10.5
  et kubectl 1.34.6. Après ce changement, reconstruire/redéployer l'image
  `ci/local-jenkins` avant d'exécuter un build de provisioning.
- Le compte AWS Academy et le mot de passe Grafana ont une portée globale dans le
  job : ils doivent rester accessibles uniquement depuis un dossier Jenkins,
  agent et daemon Docker de confiance. Une condition `when` ne protège pas une
  branche non fiable qui peut modifier le Jenkinsfile.

## Destruction manuelle après la démonstration

Ne détruisez pas depuis Jenkins. Après avoir arrêté les builds et exporté les
preuves nécessaires, exécuter localement les confirmations explicites existantes :

```powershell
.\platform\scripts\academy.ps1 -Action PreviewDestroy
# Examiner le plan de destruction et le périmètre partagé.
.\platform\scripts\academy.ps1 -Action Destroy
.\platform\scripts\academy.ps1 -Action Verify
```

Cette destruction touche la plateforme commune, y compris EKS, NAT, workers,
load balancers et les images ECR si `ecr_force_delete=true`. Le backend S3 et son
state sont conservés par le script. Ne lancez jamais ces commandes pour supprimer
uniquement une feature : supprimer l'environnement GitOps correspondant est une
opération distincte.
