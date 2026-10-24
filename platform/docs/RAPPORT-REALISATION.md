# Rapport de réalisation — plateforme Events

## Synthèse

Le dépôt plateforme a été importé sur `main`, puis finalisé sur `chore/finalisation`. Dans le dépôt applicatif, `main` a été intégré à `develop` et les changements ont été préparés sur `feature/ci-cd-pipeline`. Les deux dépôts restent locaux : aucun push, appel de provisioning AWS, accès à un cluster ou changement sur GitHub distant n'a été effectué.

Le guide `GUIDE-EXECUTION.md` annoncé dans le répertoire source n'était pas présent. Il a donc été rédigé directement dans `docs/GUIDE-EXECUTION.md` à partir de l'implémentation et des consignes approuvées.

## Réalisations

### Plateforme

- Mise en place du backend Terraform S3/DynamoDB, des exemples de configuration et des règles Git pour exclure `backend.hcl`, `terraform.tfvars`, les états et `.terraform/`. Le lockfile des fournisseurs est conservé.
- Restriction de l'API publique EKS au CIDR d'administration. Les sorties de l'EC2 DevOps sont limitées aux ports HTTP/HTTPS et au DNS du résolveur VPC.
- Ajout du compte Argo CD Jenkins avec les droits `get` et `sync` sur `events/*`.
- Ajout de l'application Argo CD `ebs-storageclass` dans le chemin de l'application racine. Elle déploie une StorageClass `gp3` chiffrée, avec `WaitForFirstConsumer` et `reclaimPolicy: Delete`.
- Ajout des rôles Ansible idempotents `sonar_config` et `github_webhook`. Le webhook GitHub applicatif utilise le jeton Vault, cible `https://jenkins.<IP>.sslip.io/github-webhook/`, et active `push` et `pull_request` au format JSON. Le guide demande les portées `repo` et `admin:repo_hook` et conserve une procédure manuelle de secours.
- Durcissement des contextes de sécurité des conteneurs applicatif, MySQL et init-container dans le chart Helm.
- Ajout des scripts backend, post-apply et destruction ordonnée, ainsi que du Makefile et de la documentation opérationnelle.

### Application

- Import du pipeline Jenkins à 17 étapes, du Dockerfile JRE 17 non-root, des paramètres Maven Nexus et des fichiers Docker/Git.
- Ajout d'Actuator, Prometheus et des trois métriques métier `fst_events_count`, `fst_participants_count` et `fst_logistics_reserved_cost`.
- Correction des smoke tests : readiness et Prometheus sont vérifiés de façon bloquante; les routes métier absentes dans une feature sont signalées comme avertissements.
- Correction de Compose pour construire l'image locale, publier `9090:8089` et lire le mot de passe depuis `.env`, ignoré par Git; `.env.example` est fourni.
- README applicatif complété avec l'équipe et les environnements, le pipeline détaillé et ses lignes, les outils, les webhooks et les 13 classes de test.
- Comparaison avec `main` : les différences du `pom.xml`, d'`application.properties` et du README se limitent aux ajouts demandés; le dashboard `docs/dashboard.png` a été conservé.

## Résultats des validations locales

| Contrôle | Résultat |
|---|---|
| `./mvnw -B clean verify` | Réussi : 73 tests, 0 échec, 0 erreur, 0 ignoré. |
| Démarrage local H2/Actuator | Readiness `UP`; Prometheus HTTP 200; les trois métriques métier sont exposées. |
| `docker build -t events-app:local .` | Réussi à partir du JAR construit et testé. |
| `docker compose config --quiet` | Réussi avec une valeur de validation temporaire; aucun conteneur n'a été démarré. |
| GroovyLint, analyse syntaxique du `Jenkinsfile` | Réussi : 0 erreur de parsing. |
| Terraform `fmt -check -recursive`, `init -backend=false`, `validate` | Réussis; aucune ressource AWS n'a été créée. |
| Helm lint, profils review/staging/prod | Réussi pour les trois profils. Le rendu prod utilise bien `storageClassName: gp3`. |
| Chart Argo CD 7.7.11 | Rendu local vérifié : compte Jenkins et droits RBAC attendus. Le manifeste `15-ebs-storageclass.yaml` est dans le chemin source de l'application racine. |
| Ansible syntax-check et ansible-lint | Réussis après installation des collections depuis leurs tags GitHub. L'installation standard Galaxy avait échoué sur une erreur HTTP 500. |
| ShellCheck | Réussi sur les trois scripts Bash. |
| `scripts/post-apply.sh --dry-run` | Réussi avec des réponses `kubectl`/DNS simulées et un montage en lecture seule; aucun fichier n'a été modifié. |
| `docker compose config --quiet` et `make help` | Réussis; Makefile vérifié sans exécuter de cible AWS. |
| Gitleaks, application et plateforme | Aucun secret détecté dans les historiques et les arbres de travail. |

### Résultats Trivy et risques

Les scans Trivy sont configurés en mode rapport dans le pipeline (`--exit-code 0`); ils ne constituent donc pas un échec de build.

- Le scan des dépendances applicatives relève **14 vulnérabilités (10 HIGH, 4 CRITICAL)** dans le `pom.xml` hérité de `main`, notamment sur Spring Boot 2.7.6/Spring Framework et MySQL Connector/J. Les versions n'ont pas été changées, conformément à la demande de conserver le POM de `main` avec seulement les dépendances d'observabilité ajoutées. Une mise à niveau nécessite une décision explicite et une validation de compatibilité.
- Le scan de la plateforme signale que l'API EKS reste publique (elle est maintenant limitée à `admin_cidr`) et que l'egress HTTP/HTTPS de l'EC2 DevOps, ainsi que l'egress par défaut du module EKS, ciblent des adresses publiques. Les ports de sortie de l'EC2 sont restreints à 80/443 et le DNS à l'adresse du résolveur VPC, mais Trivy continue de signaler ces destinations. Pour supprimer ces alertes, il faudrait décider d'un endpoint EKS privé et d'une stratégie de sortie via endpoints/proxy; ce changement d'accès n'a pas été imposé sans accord.
- Trivy a émis des avertissements de parsing sur une règle Rego téléchargée et a basculé sur ses contrôles intégrés. Les validations Terraform et Helm restent indépendantes de ces avertissements.
- Le chart a été linté, mais le comportement des conteneurs durcis n'a pas été vérifié sur un cluster réel, volontairement hors périmètre.

## Ce qui reste manuel

1. Créer le dépôt public vide `roudayn-kouka/IGL5-G2-Events-Platform`, puis pousser `main` et `chore/finalisation`; ouvrir la PR plateforme vers `main`.
2. Pousser d'abord `develop`, puis `feature/ci-cd-pipeline` dans le dépôt applicatif et ouvrir la PR vers `develop`.
3. Créer et renseigner localement les fichiers de secrets (`terraform.tfvars`, `backend.hcl`, Ansible Vault et `.env`). Le jeton GitHub doit avoir `repo` et `admin:repo_hook`.
4. Examiner le plan et les coûts AWS, puis demander/obtenir l'autorisation avant bootstrap, `apply`, configuration de l'EC2 ou interaction avec le cluster.
5. Lors de la première configuration, enregistrer immédiatement le jeton SonarQube Jenkins affiché une seule fois et générer/enregistrer le jeton du compte Argo CD Jenkins.
6. Faire approuver la mise à niveau des dépendances signalées par Trivy et décider si l'API EKS doit devenir privée et si l'egress doit passer par des endpoints/proxy.

## Index « où trouver quoi »

| Élément | Chemin |
|---|---|
| Jenkinsfile et propriétaire des branches (`ownerOf`) | Application : `Jenkinsfile` |
| README, pipeline et tests détaillés | Application : `README.md` |
| Métriques métier | Application : `src/main/java/tn/fst/eventsproject/config/BusinessMetricsConfig.java` |
| Classes de test (13) | Application : `src/test/java/tn/fst/eventsproject/controllers/` et `src/test/java/tn/fst/eventsproject/services/`; liste détaillée dans le README applicatif. |
| Webhook GitHub → Jenkins | Plateforme : `ansible/roles/github_webhook/tasks/main.yml`, `ansible/group_vars/devops/vars.yml`, `ansible/site.yml` |
| Webhook SonarQube → Jenkins | Plateforme : `ansible/roles/sonar_config/tasks/main.yml` |
| Jenkins/JCasC, job Multibranch, Slack et plugins | Plateforme : `ansible/roles/devops_stack/templates/jenkins-casc.yaml.j2`, `ansible/roles/devops_stack/files/jenkins/` |
| Terraform AWS/EKS/ECR/Argo CD | Plateforme : `terraform/*.tf`, `terraform/values/argocd.yaml.tftpl` |
| Backend Terraform et exclusions Git | Plateforme : `terraform/backend.hcl.example`, `terraform/.gitignore`, `.gitignore` |
| Rôles Ansible | Plateforme : `ansible/site.yml`, `ansible/roles/` |
| Chart Helm Events et profils | Plateforme : `gitops/charts/events-app/`, `gitops/envs/` |
| Application racine, StorageClass gp3 et projets Argo CD | Plateforme : `terraform/argocd.tf`, `gitops/platform/apps/`, `gitops/platform/storage-class/gp3.yaml` |
| Alertes Prometheus | Plateforme : `gitops/platform/monitoring-config/prometheus-rules.yaml` |
| Dashboard Grafana | Plateforme : `gitops/platform/monitoring-config/grafana-dashboard-configmap.yaml` |
| Scripts d'exploitation | Plateforme : `scripts/bootstrap-state.sh`, `scripts/post-apply.sh`, `scripts/destroy.sh` |
| Cibles d'exploitation | Plateforme : `Makefile` |
| Guide d'exécution | Plateforme : `docs/GUIDE-EXECUTION.md` |
| Schémas et rapport projet v4 | Plateforme : `docs/architecture.png`, `docs/pipeline-devops.png`, `docs/Rapport-DevOps-Events-FST-v4.pdf` |
