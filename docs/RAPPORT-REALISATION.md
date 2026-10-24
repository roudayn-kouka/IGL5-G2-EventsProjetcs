# Rapport de réalisation — dépôt unique Events

## Synthèse

Le dépôt plateforme a été importé avec son historique sous `platform/` dans le dépôt applicatif unique. Les changements sont en préparation sur `feature/ci-cd-pipeline`; la branche `gitops` est orpheline et contient uniquement les manifestes d'environnement staging/prod et son README. Aucun push, provisioning AWS, accès à un cluster ou changement sur GitHub distant n'a été effectué.

Le guide opérationnel unifié est [docs/GUIDE-EXECUTION.md](GUIDE-EXECUTION.md). Ce rapport distingue les changements réalisés, les résultats observés localement, les actions restant manuelles et les limites d'une validation sans environnement distant.

## Réalisations

### Plateforme

- Mise en place du backend Terraform S3/DynamoDB, des exemples de configuration et des règles Git pour exclure `backend.hcl`, `terraform.tfvars`, les états et `.terraform/`. Le lockfile des fournisseurs est conservé.
- L'API EKS a ses points de terminaison privé et public activés; l'accès public est limité à `admin_cidr`.
- Ajout du compte Argo CD Jenkins avec les droits `get` et `sync` sur `events/*`.
- Ajout de l'application Argo CD `ebs-storageclass` dans le chemin de l'application racine. Elle déploie une StorageClass `gp3` chiffrée, avec `WaitForFirstConsumer` et `reclaimPolicy: Delete`.
- Ajout des rôles Ansible idempotents `sonar_config` et `github_webhook`. Le webhook GitHub applicatif utilise le jeton Vault, cible `https://jenkins.<IP>.sslip.io/github-webhook/`, et active `push` et `pull_request` au format JSON. Le guide demande les portées `repo` et `admin:repo_hook` et conserve une procédure manuelle de secours.
- Durcissement des contextes de sécurité des conteneurs applicatif, MySQL et init-container dans le chart Helm.
- `post-apply.sh` écrit `argocd_server`/`apps_domain` dans le fichier local ignoré `platform/ansible/group_vars/devops/runtime.yml` (ces clés ont été retirées de `vars.yml`, qui sinon les écraserait : Ansible lit `group_vars/devops/` par ordre alphabétique). Il met à jour les hôtes staging/prod sur `gitops` dans un worktree temporaire et commit localement sans pousser. Aucun fichier suivi de `main` n'est modifié. Grafana est accessible en port-forward (`make grafana-ui`), sans ingress.
- Jenkins : étape 12 clonée sur `gitops` (`--depth 20`), push sur `gitops` avec rebase et 5 essais; étape 13 attend le SHA dans `.status.sync.revisions[]`. JCasC : `PLATFORM_REPO` = dépôt unique, `GITOPS_BRANCH=gitops`, job Multibranch avec `excludes('gitops')`.
- `platform/gitops/envs/` est retiré de `main` : son contenu est désormais sur la branche orpheline `gitops`, seule source lue par Argo CD.
- La racine Argo CD pointe sur `platform/gitops/platform/apps` depuis `main`; les sources GitOps et `platform_repo_url` utilisent le dépôt unique. L'ApplicationSet charge les manifestes de déploiement depuis la branche `gitops`.
- Ajout des scripts backend et de destruction ordonnée, du Makefile, de la branche de déploiement séparée et du guide opérationnel monorepo.

### Application

- Import du pipeline Jenkins à 17 étapes, du Dockerfile JRE 17 non-root, des paramètres Maven Nexus et des fichiers Docker/Git.
- Ajout d'Actuator, Prometheus et des trois métriques métier `fst_events_count`, `fst_participants_count` et `fst_logistics_reserved_cost`.
- Correction des smoke tests : readiness et Prometheus sont vérifiés de façon bloquante; les routes métier absentes dans une feature sont signalées comme avertissements.
- Correction de Compose pour construire l'image locale, publier `9090:8089` et lire le mot de passe depuis `.env`, ignoré par Git; `.env.example` est fourni.
- README applicatif complété avec l'équipe et les environnements, le pipeline détaillé et ses lignes, les outils, les webhooks et les 13 classes de test.
- Spring Boot est mis à niveau vers 2.7.18 avec SnakeYAML 2.2 (CVE-2022-1471 supprimée). Le Dockerfile utilise le JAR construit et testé.
- README racine et guide décrivent le monorepo, ses branches, le pipeline, les outils, les webhooks, les tests, les routines locales et l'exploitation.
- Le dashboard `docs/dashboard.png`, le rapport v4, `docker-compose.yml`, `.env.example` et le wrapper Maven sont conservés.

## Résultats des validations locales (24/10/2026)

| Contrôle | Commande / outil | Résultat |
|---|---|---|
| Maven | `./mvnw -B clean verify` (JDK 25) | **BUILD SUCCESS**, 73 tests, 0 échec. JAR : Spring Boot 2.7.18, SnakeYAML 2.2. |
| Docker | `docker build -t events-app:local .` | Image construite (345 Mo, Alpine 3.24, JRE 17, non-root). |
| Trivy image | `trivy image --severity CRITICAL --ignore-unfixed` (0.57.1) | **9 CRITICAL corrigeables** restantes, 0 dans la couche OS (détail ci-dessous). |
| Groovy | `npm-groovy-lint --failon error Jenkinsfile` | 0 erreur, 28 avertissements, 76 infos (style). |
| Terraform | `terraform fmt -check -recursive`, `init -backend=false`, `validate` (1.9.8) | Format OK; « The configuration is valid ». |
| Ansible | `ansible-playbook site.yml --syntax-check` (ansible-core 2.17) | OK. `ansible-inventory` confirme que `runtime.yml` fournit `argocd_server`/`apps_domain`; rendu JCasC : YAML valide, `GITOPS_BRANCH=gitops`, `excludes('gitops')`. |
| Helm | `helm lint` + `helm template` (3.16.3), profils review/staging/prod avec les `values.yaml` de `gitops` | 3 × lint OK; 7, 8 et 9 manifestes rendus (PVC en staging/prod, HPA en prod). |
| ApplicationSet | Rendu du template Go (générateur git `envs/*/config.json` sur `gitops`, `missingkey=error`) | `events-staging`, `events-prod`, `events-ci-cd-pipeline` : 2 sources (chart `main` / `ref: values` `gitops`), projet `events`. |
| ShellCheck | `shellcheck platform/scripts/*.sh` (0.10.0) | Aucun avertissement. |
| Gitleaks | `gitleaks detect --log-opts="--all" --redact` (8.21.2) + `--no-git` | Aucune fuite; historique complet (21 commits avec diff texte, 1 commit binaire seul, 11 merges) et arbre de travail. |
| Références obsolètes | `grep -r "Events-Platform"` (arbre + branche `gitops`) | Aucune. Seuls les messages de l'historique importé l'évoquent. |
| Provisionnement AWS / cluster | — | Non exécuté (hors autorisation). |

### Trivy : CRITICAL restantes et correction proposée

| Bibliothèque (dans `app.jar`) | Version | CVE | Corrigée dans | Origine |
|---|---|---|---|---|
| `tomcat-embed-core` | 9.0.83 | CVE-2025-24813 et 6 CVE 2026 (coyote/HTTP2, authentification digest/FORM, contraintes de sécurité) | 9.0.121 (branche 9.0.x) | Version gérée par Spring Boot 2.7.18 (dernière 2.7 OSS) |
| `spring-web` | 5.3.31 | CVE-2016-1000027 (`HttpInvokerServiceExporter`) | 6.0.0 | Spring Framework 5.3 |
| `spring-webmvc` | 5.3.31 | CVE-2026-47884 (`XsltView`) | 7.0.9 | Spring Framework 5.3 |

**Correction minimale proposée (non appliquée)** :

1. `pom.xml` : `<tomcat.version>9.0.121</tomcat.version>` dans `<properties>`. Testé localement avec `-Dtomcat.version=9.0.121` : 73 tests verts, Trivy passe de 9 à **2** CRITICAL.
2. Les deux CVE Spring ne sont corrigées que dans Spring 6/7, donc Spring Boot 3/4 et Java 17+ (migration `javax` → `jakarta` hors périmètre). L'application n'utilise ni `HttpInvokerServiceExporter` ni `XsltView` (`grep` vide dans `src/`). Proposition : un fichier `.trivyignore` qui documente ces deux identifiants avec leur justification, sinon le mode strict (étape 9 sur `release/*` et `main`) bloquera.

## Ce qui reste manuel

1. Après revue et validation des branches, pousser `develop`, `feature/ci-cd-pipeline`, puis `gitops`; ouvrir ensuite la Pull Request `feature/ci-cd-pipeline` → `develop`.
2. Créer et renseigner localement les fichiers de secrets (`platform/terraform/terraform.tfvars`, `platform/terraform/backend.hcl`, Ansible Vault et `.env`). Le jeton GitHub doit avoir les portées `repo` et `admin:repo_hook`.
3. Examiner le plan et les coûts AWS, puis demander/obtenir l'autorisation avant bootstrap, `apply`, configuration de l'EC2 ou interaction avec le cluster.
4. Lors de la première configuration, enregistrer immédiatement le jeton SonarQube Jenkins affiché une seule fois et générer/enregistrer le jeton du compte Argo CD Jenkins.
5. Décider de la correction Trivy (Tomcat 9.0.121 + `.trivyignore` justifié), puis valider le comportement des conteneurs et des ressources sur un cluster de test.

## Index « où trouver quoi »

| Élément | Chemin |
|---|---|
| Jenkinsfile, `ownerOf()` et pipeline 17 étapes | `Jenkinsfile` |
| Métriques métier | `src/main/java/tn/fst/eventsproject/config/BusinessMetricsConfig.java` |
| Classes de test (13) | `src/test/java/tn/fst/eventsproject/controllers/` et `src/test/java/tn/fst/eventsproject/services/`; détail dans `README.md` |
| Webhook GitHub → Jenkins (création/idempotence) | `platform/ansible/roles/github_webhook/tasks/main.yml`; appel dans `platform/ansible/site.yml`; URL dans `platform/ansible/group_vars/devops/vars.yml` |
| Webhook SonarQube → Jenkins | `platform/ansible/roles/sonar_config/tasks/main.yml`; consommation `Jenkinsfile` |
| Jenkins/JCasC, job Multibranch, Slack et plugins | `platform/ansible/roles/devops_stack/templates/jenkins-casc.yaml.j2`, `platform/ansible/roles/devops_stack/files/jenkins/` |
| Terraform AWS/EKS/ECR/Argo CD | `platform/terraform/*.tf`, `platform/terraform/values/argocd.yaml.tftpl` |
| Backend Terraform et exclusions Git | `platform/terraform/backend.hcl.example`, `platform/terraform/.gitignore`, `.gitignore` |
| Rôles Ansible | `platform/ansible/site.yml`, `platform/ansible/roles/` |
| Chart Helm et profils Events | `platform/gitops/charts/events-app/`, branche `gitops:envs/` |
| Application racine, StorageClass gp3 et AppProject | `platform/terraform/argocd.tf`, `platform/gitops/platform/apps/`, `platform/gitops/platform/storage-class/gp3.yaml` |
| ApplicationSet multi-sources | `platform/gitops/platform/apps/40-events-environments.yaml` |
| Alertes Prometheus | `platform/gitops/platform/monitoring-config/prometheus-rules.yaml` |
| Dashboard Grafana | `platform/gitops/platform/monitoring-config/grafana-dashboard-configmap.yaml` |
| Scripts d'exploitation | `platform/scripts/bootstrap-state.sh`, `platform/scripts/post-apply.sh`, `platform/scripts/destroy.sh` |
| Makefile et cibles d'exploitation | `platform/Makefile` |
| Guide d'exécution | `docs/GUIDE-EXECUTION.md` |
| Schémas, rapport projet v4 et rapport de réalisation | `docs/architecture.png`, `docs/pipeline-devops.png`, `docs/Rapport-DevOps-Events-FST-v4.pdf`, `docs/RAPPORT-REALISATION.md` |
