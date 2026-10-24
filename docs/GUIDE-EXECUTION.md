# Guide d'exécution — dépôt unique Events

Ce guide suit les fichiers présents dans ce dépôt. Les commandes AWS qui créent ou détruisent des ressources doivent être exécutées par une personne autorisée, après examen du plan et des coûts. Elles n'ont pas été lancées pendant la réalisation.

Les commandes shell supposent Linux, macOS, WSL ou Git Bash avec GNU Make et Bash. Sous Windows, exécutez-les depuis WSL ou Git Bash. Les fichiers de secrets réels (`terraform.tfvars`, `backend.hcl`, `vault.yml`, `.env`) ne doivent jamais être ajoutés à Git.

## 1. Prérequis

- AWS CLI configuré pour le compte/lab autorisé dans `eu-west-3`, avec accès à EKS, EC2, ECR, IAM, S3, DynamoDB et aux ressources nécessaires.
- Terraform `>= 1.6`, GNU Make, Bash, Git et Python 3.
- `kubectl`, `dig`, `curl`, `ansible-playbook`, `ansible-galaxy`, `ansible-vault`.
- Clé publique SSH locale correspondant à `ssh_public_key_path` dans les variables Terraform.
- Comptes/jetons de l'équipe pour GitHub, SonarQube et Slack. Le jeton GitHub doit inclure les portées `repo` et `admin:repo_hook` pour créer le webhook du dépôt.

Depuis la racine du dépôt unique :

```bash
cd platform
make help
```

Le dépôt a deux historiques : `main`/`develop`/`feature/*` (code + `platform/`) et la branche orpheline `gitops` (uniquement `envs/<env>/`). La branche `gitops` doit être poussée **avant** `make apply` : l'ApplicationSet `events-environments` la lit dès l'amorçage d'Argo CD.

```bash
git push origin gitops
```

## 2. Préparer le backend Terraform distant

Le backend S3 doit exister avant d'initialiser l'état principal. Cette étape crée des ressources AWS facturables :

```bash
make bootstrap-state
```

Le script crée un bucket versionné, chiffré AES256 et protégé contre l'accès public, ainsi qu'une table DynamoDB `fst-events-tflock` à la demande. Le bucket est suffixé par l'identifiant du compte et la région. Copier le modèle et y reporter exactement le bucket affiché :

```bash
cp terraform/backend.hcl.example terraform/backend.hcl
```

Éditez `terraform/backend.hcl` et remplacez `<account-id>` par l'identifiant affiché. Le fichier doit contenir :

```hcl
bucket         = "fst-events-tfstate-<account-id>-eu-west-3"
key            = "platform/terraform.tfstate"
region         = "eu-west-3"
dynamodb_table = "fst-events-tflock"
encrypt        = true
```

Puis préparez les entrées Terraform (les vraies valeurs restent locales et ignorées) :

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Renseignez l'adresse IP d'administration au format CIDR, le mot de passe Grafana et les secrets Slack, puis initialisez le backend :

```bash
make init
```

`admin_cidr` protège l'accès SSH à l'EC2 DevOps et limite l'endpoint public de l'API EKS à l'adresse d'administration. Remplacez-le par votre adresse réelle au format `/32`; ne l'élargissez pas à `0.0.0.0/0`. L'endpoint privé EKS est aussi activé (`cluster_endpoint_private_access = true`).

Si l'IP publique d'administration change, mettez à jour `admin_cidr` dans `terraform/terraform.tfvars` avec la nouvelle IP au format `/32`, puis appliquez la configuration. Si l'API EKS est injoignable depuis la machine d'administration, utilisez l'apply sans rafraîchir l'état distant, configurez le kubeconfig, puis vérifiez les nœuds :

```bash
# Depuis platform/
terraform -chdir=terraform apply -refresh=false
make kubeconfig
kubectl get nodes
```

Ne désactivez pas l'accès privé et ne remplacez pas le CIDR par une règle ouverte. Si `kubectl get nodes` échoue encore, vérifiez l'IP/CIDR, le contexte AWS et la connectivité avant toute nouvelle tentative.

## 3. Vérifier puis créer l'infrastructure

Avant toute création, formatez et validez la configuration, puis examinez le plan. `make plan` est en lecture seule, mais peut nécessiter des identifiants AWS :

```bash
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
make plan
```

Vérifiez le compte AWS, la région, les ressources et les coûts estimés. Seulement après cette revue et une autorisation explicite :

```bash
make apply
```

Configurez le contexte Kubernetes et vérifiez que le cluster répond :

```bash
make kubeconfig
kubectl get nodes
kubectl -n argocd get applications
```

Terraform génère l'inventaire Ansible dans `ansible/inventory/hosts.ini` et les valeurs de relais dans `ansible/group_vars/devops/terraform.yml`. Ces fichiers sont produits localement après `apply`.

## 4. Découvrir les adresses des load balancers

Argo CD déploie l'ingress et le monitoring depuis le dépôt; le service Argo CD et l'ingress ont chacun un NLB. Après que les deux Services aient reçu leur DNS, exécutez :

```bash
make post-apply
```

Le script attend au maximum 900 secondes, résout le NLB public en IPv4, puis écrit `argocd_server` et `apps_domain` dans `ansible/group_vars/devops/runtime.yml`, ignoré par Git et chargé automatiquement par Ansible. Il met aussi à jour `host` dans `envs/staging/values.yaml` et `envs/prod/values.yaml` de la branche `gitops`, dans un worktree temporaire (la branche courante et `main` ne sont pas touchées), puis crée un commit local sans push. Publiez-le ensuite :

```bash
git push origin gitops
```

Aucun fichier suivi de `main` n'est modifié : `runtime.yml` est ignoré par Git, et Grafana n'a pas d'ingress. Grafana se consulte en port-forward (section 6). Le délai d'attente est réglable :

```bash
POST_APPLY_TIMEOUT_SECONDS=30 make post-apply
```

`scripts/post-apply.sh --dry-run` affiche les changements calculés sans les écrire; il nécessite néanmoins `kubectl`, les deux adresses de service et `dig` :

```bash
POST_APPLY_TIMEOUT_SECONDS=30 bash scripts/post-apply.sh --dry-run
```

## 5. Préparer Ansible Vault et configurer les outils

Copiez l'exemple, renseignez les secrets en local, puis chiffrez-le :

```bash
cp ansible/group_vars/devops/vault.yml.example ansible/group_vars/devops/vault.yml
```

Dans `vault.yml`, renseignez notamment les mots de passe administrateur Jenkins, Nexus, base SonarQube et SonarQube, le nom/jeton GitHub, ainsi que les jetons initiaux Slack si disponibles. Pour la création automatisée du webhook GitHub, `vault_github_token` doit être un jeton autorisé sur le dépôt avec `repo` et `admin:repo_hook`.

```bash
ansible-vault encrypt ansible/group_vars/devops/vault.yml
make configure
```

Le premier passage configure la stack, change `admin/admin` dans SonarQube, crée le webhook SonarQube interne et le webhook GitHub `push`/`pull_request`. Le rôle SonarQube peut créer un jeton nommé `jenkins`; Ansible l'affiche une seule fois. Copiez immédiatement cette valeur dans `vault_sonar_token` du Vault. SonarQube ne permet pas de relire un jeton existant. Si le jeton a déjà été créé mais n'a pas été sauvegardé, révoquez-le dans SonarQube puis relancez le playbook pour en créer un nouveau.

Une fois le compte Jenkins Argo CD prêt, ouvrez un tunnel dans un terminal :

```bash
make argocd-ui
```

Dans un autre terminal, récupérez temporairement le mot de passe initial administrateur et connectez-vous :

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
argocd login localhost:8080 --username admin --password '<mot-de-passe-affiché>' --grpc-web --plaintext
argocd account generate-token --account jenkins --server localhost:8080 --grpc-web --plaintext
```

Enregistrez le jeton affiché comme `vault_argocd_token` dans le Vault. Après avoir mis à jour et rechiffré le Vault, relancez :

```bash
ansible-vault encrypt ansible/group_vars/devops/vault.yml
make configure
```

Le compte Argo CD `jenkins` est limité à `applications,get` et `applications,sync` sur `events/*`; ne partagez pas le jeton initial administrateur.

### Webhooks manuels de secours

Le rôle `github_webhook` crée automatiquement le webhook applicatif. Si l'API GitHub n'est pas accessible ou que l'autorisation manque, dans les paramètres **Settings → Webhooks** du dépôt `IGL5-G2-EventsProjetcs`, ajoutez :

- URL : `https://jenkins.<IP-EC2>.sslip.io/github-webhook/`
- Content type : `application/json`
- Événements : `push` et `pull_request`
- Webhook actif.

Le rôle `sonar_config` crée également le webhook SonarQube. En secours, dans **Administration → Configuration → Webhooks**, ajoutez le nom `jenkins` et l'URL `http://jenkins:8080/sonarqube-webhook/` (adresse interne Docker, et non `localhost`).

## 6. Vérifier les applications GitOps

```bash
make status
kubectl get storageclass gp3
kubectl -n ingress-nginx get service ingress-nginx-controller
kubectl -n monitoring get pods
```

La StorageClass `gp3` est chiffrée et provisionnée par EBS CSI avec `WaitForFirstConsumer` et `reclaimPolicy: Delete`; son Application cluster-scope est déclarée dans `platform/gitops/platform/apps/15-ebs-storageclass.yaml` et incluse par l'application racine. Le chart applicatif expose `/events/actuator/health/readiness` et `/events/actuator/prometheus`. Les règles Prometheus sont dans `platform/gitops/platform/monitoring-config/prometheus-rules.yaml`; le dashboard Grafana est dans `platform/gitops/platform/monitoring-config/grafana-dashboard-configmap.yaml`.

Grafana n'a pas de nom d'hôte dynamique à committer. Pour y accéder localement :

```bash
make grafana-ui
```

Puis ouvrez `http://localhost:3000`; interrompez le port-forward avec `Ctrl+C`.

## 7. Lancer localement l'application

Depuis la racine du dépôt, construire d'abord le JAR testé, puis démarrer Compose :

```bash
cp .env.example .env
```

Remplacez `change-me` dans `.env` par un mot de passe local non réutilisé :

```bash
./mvnw -B clean verify
docker compose up --build
```

L'application est publiée sur `http://localhost:9090/events/`; la sonde de santé est `http://localhost:9090/events/actuator/health/readiness` et les métriques sont sur `http://localhost:9090/events/actuator/prometheus`. Arrêt local :

```bash
docker compose down
```

Le JAR est nécessaire au build Docker et n'est pas commité. Le fichier `.env` doit rester ignoré par Git.

## 8. Exécuter le pipeline sur une feature

Depuis la racine du dépôt, créez la branche depuis `develop`, validez localement puis poussez-la :

```bash
git switch develop
git pull --ff-only origin develop
git switch -c feature/ma-feature
./mvnw -B clean verify
git push -u origin feature/ma-feature
```

Jenkins détecte la branche. Les étapes 1 à 10 construisent, testent et publient; la promotion GitOps met à jour `envs/ma-feature/` sur la branche `gitops`; Argo CD crée l'environnement correspondant. Une Pull Request de feature doit viser `develop` et ne déploie pas. La branche `gitops` ne contient pas de Jenkinsfile et est explicitement exclue du Multibranch, afin que ses commits n'entraînent pas de nouvelle build.

### Supprimer un environnement de feature (après fusion dans `develop`)

La suppression se fait sur la branche `gitops`, jamais sur `main` :

```bash
git fetch origin gitops
git switch gitops
git pull --rebase origin gitops
git rm -r envs/<nom-feature>
git commit -m "chore(gitops): suppression de l'environnement <nom-feature>"
git push origin gitops
git switch -          # retour à la branche de travail
```

L'ApplicationSet ne trouve plus `envs/<nom-feature>/config.json` : il supprime l'Application `events-<nom-feature>`, et son finalizer supprime les ressources du namespace. Vérification :

```bash
kubectl -n argocd get applications
kubectl get namespace events-<nom-feature>   # disparaît une fois la suppression terminée
```

Ne supprimez jamais `envs/staging` ni `envs/prod`. Pour annuler une suppression, `git revert` du commit sur `gitops` recrée l'environnement.

## 9. Contrôles locaux sans action AWS

Depuis le dépôt unique, les commandes d'infrastructure s'exécutent depuis `platform/` :

```bash
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform validate
ansible-galaxy collection install -r ansible/requirements.yml
ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml --syntax-check
helm lint gitops/charts/events-app -f gitops/charts/events-app/values-review.yaml
helm lint gitops/charts/events-app -f gitops/charts/events-app/values-staging.yaml
helm lint gitops/charts/events-app -f gitops/charts/events-app/values-prod.yaml
# Rendu avec les valeurs réelles de la branche gitops (exemple staging)
git show gitops:envs/staging/values.yaml > /tmp/staging-values.yaml
helm template events-staging gitops/charts/events-app -n events-staging   -f gitops/charts/events-app/values-staging.yaml -f /tmp/staging-values.yaml
bash -n scripts/*.sh && shellcheck scripts/*.sh
```

Depuis l'application (racine du dépôt) :

```bash
cd ..
./mvnw -B clean verify
docker build -t events-app:local .
```

Depuis la racine du dépôt unique, Gitleaks vérifie l'historique complet sans afficher les valeurs détectées :

```bash
docker run --rm -v "$PWD:/repo" zricethezav/gitleaks:v8.21.2 detect --source /repo --log-opts="--all" --redact --no-banner
```

`terraform init -backend=false`, les vérifications de syntaxe, les tests et le build local ne provisionnent pas d'infrastructure. `terraform plan`, la configuration Ansible sur l'EC2, les appels Argo CD à un cluster réel et toute commande `apply`/`destroy` sont hors validation locale et nécessitent les autorisations correspondantes.

## 10. Détruire l'infrastructure proprement

Avant de supprimer les ressources, vérifiez les environnements et volumes à conserver. Le script désactive l'auto-sync de l'application racine et de l'ingress, supprime l'ApplicationSet et les environnements enfants, supprime le service public, convertit le service Argo CD en `ClusterIP`, puis attend la disparition des load balancers du cluster. La dernière étape demande confirmation avant Terraform :

```bash
make destroy
```

Si des load balancers subsistent ou si l'attente expire, le script s'arrête sans lancer `terraform destroy`; diagnostiquez les ressources restantes avant de relancer. Les données MySQL de staging/prod sont sur des PVC dont la StorageClass a `reclaimPolicy: Delete` : leur suppression est destructive.
