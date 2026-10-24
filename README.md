<p align="center">
  <img src="src/main/resources/static/img/logo-fst.jpg" alt="Faculté des Sciences de Tunis" height="110">
</p>

<h1 align="center">Events Project — Gestion des événements</h1>

<p align="center">
  Application Spring Boot de gestion des événements, des participants et de la logistique<br>
  <b>Faculté des Sciences de Tunis</b> · Université de Tunis El Manar · IGL5 — Groupe 2
</p>

<p align="center">
  <img alt="Java" src="https://img.shields.io/badge/Java-8%2B-000098">
  <img alt="Spring Boot" src="https://img.shields.io/badge/Spring%20Boot-2.7.18-6DB33F">
  <img alt="MySQL" src="https://img.shields.io/badge/MySQL-8-4479A1">
  <img alt="Tests" src="https://img.shields.io/badge/tests-JUnit%20%2B%20Mockito-ccce01">
  <img alt="Coverage" src="https://img.shields.io/badge/coverage-JaCoCo-000098">
</p>

---

## Sommaire

- [Présentation](#présentation)
- [Dashboard](#dashboard)
- [Stack technique](#stack-technique)
- [Architecture](#architecture)
- [Modèle de données](#modèle-de-données)
- [Démarrage rapide](#démarrage-rapide)
- [API REST](#api-rest)
- [Tests et couverture](#tests-et-couverture)
- [Pipeline CI/CD · DevSecOps · GitOps](#pipeline-cicd--devsecops--gitops)
- [Sécurité](#sécurité)
- [Structure du projet](#structure-du-projet)
- [Workflow Git](#workflow-git)
- [Dépannage](#dépannage)

---

## Présentation

**Events Project** permet d'organiser les événements de la faculté (journées portes ouvertes, hackathons, conférences, forums…) :

- **Événements** : création, dates de début et de fin, coût calculé automatiquement.
- **Participants** : gestion CRUD et affectation d'une tâche (`ORGANISATEUR`, `ANIMATEUR`, `SERVEUR`, `INVITE`).
- **Logistique** : matériel et services rattachés à un événement (prix unitaire, quantité, réservé ou non).
- **Statistiques** : par événement et globales (participants par tâche, taux de réservation, coût de la logistique réservée).
- **Dashboard web** aux couleurs de la FST, servi directement par l'application.
- **Tâche planifiée** (`@Scheduled`) qui recalcule régulièrement le coût des événements.
- **Aspect AOP** (`PerformanceAspect`) qui journalise le temps d'exécution de chaque méthode des services.

## Dashboard

Une fois l'application lancée : **<http://localhost:8089/events/>**

<p align="center">
  <img src="docs/dashboard.png" alt="Aperçu du dashboard" width="900">
</p>

| Zone | Contenu |
|---|---|
| Indicateurs clés | Nombre d'événements (à venir / passés), participants, logistique réservée, coût total réservé |
| Graphiques | Coût de la logistique réservée par événement · participants par tâche · composition des équipes par événement |
| Prochains événements | Frise chronologique avec compte à rebours |
| Tableau des événements | Recherche, filtre par intervalle de dates, durée, statut (à venir / en cours / terminé) |
| Participants et logistique | Listes filtrables, changement de tâche directement dans le tableau |
| Bouton « Ajouter » | Création d'un événement (avec ses participants), d'un participant ou d'une logistique |

> Le dashboard est une page statique (`src/main/resources/static/index.html`) qui consomme l'API REST. Chart.js est embarqué dans le projet, le dashboard fonctionne donc **sans connexion internet**.

**Données de démonstration** : au premier démarrage, si la base est vide, 6 événements, 12 participants et leur logistique sont insérés automatiquement (`DemoDataLoader`). Pour désactiver ce comportement :

```properties
# src/main/resources/application.properties
app.demo-data=false
```

## Stack technique

| Couche | Technologies |
|---|---|
| Langage | Java 8+ (bytecode cible 8; JDK 17 recommandé) |
| Framework | Spring Boot 2.7.18 (Web, Data JPA, AOP, Scheduling, Actuator) |
| Persistance | Hibernate / JPA · MySQL 8 (application) · H2 en mémoire (tests) |
| Productivité | Lombok 1.18.46 |
| Tests | JUnit 4 & 5 · Mockito · MockMvc · Spring Boot Test |
| Qualité | JaCoCo 0.8.15 (couverture de code) |
| Front | HTML / CSS / JavaScript · Chart.js 4.4.1 |
| Build | Maven (wrapper `mvnw` inclus) |

## Architecture

Architecture en couches classique **Controller → Service → Repository → Base de données**.

```mermaid
flowchart LR
    UI["Dashboard<br/>static/index.html"] -->|HTTP / JSON| C
    Client["Postman / curl"] -->|HTTP / JSON| C
    subgraph Spring Boot :8089/events
        C["Controllers<br/>Event · Participant · Logistics · EventStats"]
        S["Services<br/>IEventServices · IParticipantServices<br/>ILogisticsService · IEventStatsService"]
        R["Repositories<br/>Spring Data JPA"]
        A(["PerformanceAspect<br/>AOP"])
        SCH(["calculCout()<br/>@Scheduled"])
        C --> S --> R
        A -. mesure .-> S
        SCH -.-> S
    end
    R --> DB[("MySQL<br/>eventsProject")]
```

## Modèle de données

```mermaid
classDiagram
    class Event {
        int idEvent
        String description
        LocalDate dateDebut
        LocalDate dateFin
        float cout
    }
    class Participant {
        int idPart
        String nom
        String prenom
        Tache tache
    }
    class Logistics {
        int idLog
        String description
        boolean reserve
        float prixUnit
        int quantite
    }
    class Tache {
        <<enumeration>>
        INVITE
        ORGANISATEUR
        SERVEUR
        ANIMATEUR
    }
    Participant "*" -- "*" Event : participe à
    Event "1" --> "*" Logistics : utilise
    Participant --> Tache
```

- `Participant` est le **côté propriétaire** de la relation `ManyToMany` avec `Event`.
- `Event → Logistics` est une relation `OneToMany` unidirectionnelle, chargée en `EAGER`.
- Le coût d'un événement = somme de `prixUnit × quantite` des logistiques **réservées**.

## Démarrage rapide

### Prérequis

- **JDK 17** recommandé (le `pom.xml` est configuré pour les JDK 8 à 26)
- **MySQL 8** démarré sur `localhost:3306` (XAMPP, WAMP, Docker… au choix)
- Maven 3.6+ (ou le wrapper `mvnw` fourni)

### 1. Cloner le dépôt

```bash
git clone <url-du-depot>
cd IGL5-G2-EventsProjetcs
```

### 2. Configurer la base de données

La base `eventsProject` est créée automatiquement au démarrage. Par défaut, l'utilisateur est `root` sans mot de passe. Pour modifier, éditez `src/main/resources/application.properties` :

```properties
spring.datasource.url=jdbc:mysql://localhost:3306/eventsProject?createDatabaseIfNotExist=true&serverTimezone=UTC
spring.datasource.username=root
spring.datasource.password=
```

> Pour lancer MySQL rapidement avec Docker :
> ```bash
> docker run -d --name mysql-events -p 3306:3306 -e MYSQL_ALLOW_EMPTY_PASSWORD=yes mysql:8
> ```

### 3. Lancer l'application

```bash
mvn spring-boot:run
# ou, sous Windows : mvnw.cmd spring-boot:run
```

| Ressource | URL |
|---|---|
| Dashboard | <http://localhost:8089/events/> |
| Base de l'API | `http://localhost:8089/events` |

### 4. Construire le JAR

```bash
mvn clean package
java -jar target/eventsProject-1.0.0-SNAPSHOT.jar
```

## API REST

Toutes les routes sont préfixées par le context-path **`/events`** (ex. `http://localhost:8089/events/participant/all`).

### Statistiques — `/event-stats`

| Méthode | Route | Description |
|---|---|---|
| `GET` | `/event-stats` | Statistiques de tous les événements, triées par date |
| `GET` | `/event-stats/summary` | Indicateurs globaux du dashboard |
| `GET` | `/event-stats/{id}` | Statistiques d'un événement (`404` s'il n'existe pas) |
| `GET` | `/event-stats/upcoming` | Statistiques des événements à venir |
| `GET` | `/event-stats/between/{d1}/{d2}` | Événements dont la date de début est entre `d1` et `d2` (`yyyy-MM-dd`, `400` si `d1 > d2`) |

<details>
<summary>Exemple de réponse — <code>GET /event-stats/1</code></summary>

```json
{
  "idEvent": 1,
  "description": "Journée Portes Ouvertes FST",
  "dateDebut": "2026-10-27",
  "dateFin": "2026-10-27",
  "dureeJours": 1,
  "nbParticipants": 6,
  "participantsParTache": { "INVITE": 3, "ORGANISATEUR": 1, "SERVEUR": 1, "ANIMATEUR": 1 },
  "nbLogistics": 4,
  "nbLogisticsReservees": 3,
  "coutLogistiqueReservee": 2640.0
}
```
</details>

<details>
<summary>Exemple de réponse — <code>GET /event-stats/summary</code></summary>

```json
{
  "nbEvents": 6,
  "nbEventsAVenir": 4,
  "nbParticipants": 12,
  "nbLogistics": 18,
  "nbLogisticsReservees": 14,
  "tauxReservation": 77.78,
  "coutTotalLogistiqueReservee": 10960.0,
  "participantsParTache": { "INVITE": 6, "ORGANISATEUR": 2, "SERVEUR": 2, "ANIMATEUR": 2 }
}
```
</details>

### Événements — `/event`

| Méthode | Route | Description |
|---|---|---|
| `POST` | `/event/addPart` | Ajouter un participant |
| `POST` | `/event/addEvent` | Créer un événement et l'affecter aux participants listés dans `participants` |
| `POST` | `/event/addEvent/{id}` | Créer un événement et l'affecter au participant `{id}` |
| `PUT` | `/event/addAffectLog/{description}` | Ajouter une logistique à l'événement portant cette description |
| `GET` | `/event/getLogs/{d1}/{d2}` | Logistiques réservées des événements entre deux dates |

### Participants — `/participant`

| Méthode | Route | Description |
|---|---|---|
| `POST` | `/participant/add` | Créer un participant |
| `GET` | `/participant/all` | Lister tous les participants |
| `GET` | `/participant/{id}` | Détail d'un participant (`404` s'il n'existe pas) |
| `PUT` | `/participant/update/{id}` | Modifier nom, prénom et tâche |
| `PUT` | `/participant/{id}/tache/{tache}` | Changer uniquement la tâche |
| `DELETE` | `/participant/delete/{id}` | Supprimer un participant |

### Logistique — `/logistics`

| Méthode | Route | Description |
|---|---|---|
| `POST` | `/logistics` | Créer une logistique (`201`) |
| `PUT` | `/logistics` | Modifier une logistique |
| `GET` | `/logistics` | Lister toutes les logistiques |
| `GET` | `/logistics/{id}` | Détail d'une logistique |
| `GET` | `/logistics/reserved` | Lister les logistiques réservées |
| `GET` | `/logistics/{id}/cout` | Coût total (`prixUnit × quantite`) |
| `DELETE` | `/logistics/{id}` | Supprimer une logistique (`204`) |

### Exemples `curl`

```bash
# Créer un participant
curl -X POST http://localhost:8089/events/participant/add \
  -H "Content-Type: application/json" \
  -d '{"nom":"Tounsi","prenom":"Ahmed","tache":"ORGANISATEUR"}'

# Créer un événement affecté aux participants 1 et 2
curl -X POST http://localhost:8089/events/event/addEvent \
  -H "Content-Type: application/json" \
  -d '{"description":"Hackathon","dateDebut":"2026-11-05","dateFin":"2026-11-06","participants":[{"idPart":1},{"idPart":2}]}'

# Ajouter une logistique réservée à cet événement
curl -X PUT http://localhost:8089/events/event/addAffectLog/Hackathon \
  -H "Content-Type: application/json" \
  -d '{"description":"Pause-café","reserve":true,"prixUnit":6,"quantite":120}'

# Consulter les statistiques globales
curl http://localhost:8089/events/event-stats/summary
```

## Tests et couverture

Chaque fonctionnalité est testée de deux façons :

| Type | Principe | Base de données |
|---|---|---|
| **Avec Mockito** (`*MockTest`, `*MockitoTest`) | Repositories ou services simulés, test unitaire rapide | Aucune |
| **Sans Mockito** (`*Test`, `*IntegrationTest`) | Contexte Spring complet, vrais services et repositories | H2 en mémoire |

| Fonctionnalité | Tests avec Mockito | Tests sans Mockito |
|---|---|---|
| Événements | `EventServicesMockTest` | `EventServicesImplTest` |
| Participants | `ParticipantServicesImplMockitoTest`, `ParticipantRestControllerMockitoTest` | `ParticipantServicesImplIntegrationTest`, `ParticipantRestControllerIntegrationTest` |
| Logistique | `LogisticsServiceImplMockTest`, `LogisticsControllerMockTest` | `LogisticsServiceImplTest`, `LogisticsControllerTest` |
| Statistiques | `EventStatsServiceImplMockTest`, `EventStatsControllerMockTest` | `EventStatsServiceImplIntegrationTest` |

```bash
# Lancer tous les tests (rapport JaCoCo généré automatiquement)
mvn clean test

# Lancer une seule classe de test
mvn test -Dtest=EventStatsServiceImplMockTest
```

Le rapport de couverture est disponible dans **`target/site/jacoco/index.html`**.

> Les tests utilisent `src/test/resources/application.properties` (H2 en mémoire) : **MySQL n'est pas nécessaire pour lancer les tests**.

## Pipeline CI/CD · DevSecOps · GitOps

Le pipeline est défini dans [`Jenkinsfile`](Jenkinsfile), exécuté par un job Jenkins Multibranch. Il suit le flux **push → Jenkins → Amazon ECR → branche `gitops` de ce dépôt → Argo CD → EKS → supervision**. Jenkins construit, teste et publie; il ne déploie pas directement sur Kubernetes. Il met à jour `envs/<environnement>/` sur la branche `gitops`; Argo CD synchronise ensuite le cluster.

Le dépôt unique rassemble l'application à la racine et l'infrastructure dans [`platform/`](platform/). Le schéma [docs/architecture.png](docs/architecture.png) illustre le flux : GitHub déclenche Jenkins, Jenkins publie l'image ECR et le commit GitOps, Argo CD déploie sur EKS, puis Prometheus, Alertmanager et Grafana supervisent les workloads.

<p align="center">
  <img src="docs/architecture.png" alt="Architecture DevOps GitOps" width="950">
</p>

### Équipe et environnements

| Membre | Branche | Feature | Environnement Kubernetes |
|---|---|---|---|
| Roudayna Kouka | `feature/event-statistics` | Statistiques et tableau de bord | `events-event-statistics` |
| Roudayna Kouka | `feature/ci-cd-pipeline` | Finalisation CI/CD, DevSecOps et GitOps | `events-ci-cd-pipeline` |
| Farah Baraket | `feature/participant` | Participants | `events-participant` |
| Ahlem Mastouri | `feature/logistics` | Logistique | `events-logistics` |
| Nour Mustapha | `feature/event` | Événements | `events-event` |
| Emna Ouarteni | `feature/feedback` | Avis et notes | `events-feedback` |

### Branches et flux de déploiement

```mermaid
flowchart LR
    subgraph code["Historique code + plateforme (Jenkinsfile présent)"]
        F["feature/*"] -- "Pull Request" --> D["develop"]
        D -- "release/* puis merge" --> M["main"]
    end
    subgraph deploy["Branche orpheline (aucun Jenkinsfile)"]
        G["gitops<br/>envs/&lt;env&gt;/config.json<br/>envs/&lt;env&gt;/values.yaml"]
    end
    F & D & M -- "webhook" --> J["Jenkins Multibranch<br/>(exclut gitops)"]
    J -- "étape 12 : commit envs/&lt;env&gt;/" --> G
    M -- "chart Helm + apps Argo CD<br/>platform/gitops/" --> A["Argo CD"]
    G -- "ApplicationSet + values (ref: values)" --> A
    A --> K["EKS : events-&lt;env&gt;"]
```

| Branche | Contenu | Construite par Jenkins | Déploie vers |
|---|---|---|---|
| `main` | Application + `platform/`. Source de l'application racine Argo CD (`platform/gitops/platform/apps`) et du chart Helm. | Oui | `events-prod` après approbation manuelle |
| `develop` | Intégration des features. | Oui | `events-staging` |
| `feature/*` | Une fonctionnalité par membre; fusion dans `develop` par Pull Request (PR = CI sans déploiement). | Oui | `events-<feature>` (environnement éphémère) |
| `release/*`, `hotfix/*` | Stabilisation d'une version / correctif urgent vers `main`. | Oui (Trivy strict) | Aucun |
| `gitops` | Orpheline : uniquement `envs/<env>/{config.json,values.yaml}` et un README. | **Non** (exclue du Multibranch) | Lue par Argo CD |

**Pourquoi `gitops` est séparée.** Jenkins pousse un commit à chaque déploiement. Sur `main` ou `develop`, ce commit déclencherait le webhook, donc un nouveau build, qui pousserait à nouveau : une boucle infinie, plus un historique applicatif pollué par des commits de déploiement. Sur une branche orpheline sans Jenkinsfile et exclue du job Multibranch (`excludes('gitops')`), le commit de promotion ne déclenche rien côté Jenkins; seul Argo CD le lit. Le chart reste versionné avec le code sur `main`, l'état des environnements est versionné à part : un retour arrière de déploiement est un simple `git revert` sur `gitops`.

### Les 17 étapes

Les numéros sont ceux du rapport de projet : l'étape 0 est le déclenchement webhook, les contrôles 4a/4b et 14a/14b sont parallèles, et l'étape 16 est la supervision continue. Les numéros de ligne ci-dessous pointent vers le stage Jenkins ou le bloc `post` qui l'implémente.

| Nº | Stage Jenkins | Outil(s) | Traitement | Produit | Bloquant ? | Jenkinsfile |
|---:|---|---|---|---|---|---:|
| 0 | Déclenchement (hors stage) | GitHub, Jenkins Multibranch | Webhook push/PR et découverte de branche. | Exécution Jenkins | Déclencheur | `platform/ansible/roles/github_webhook/`; JCasC |
| 1 | `Contexte & garde GitFlow` | Groovy, Git | Valide branche/PR; déduit owner, environnement, version et sévérité. | Variables de build | Oui | 46–90 |
| 2 | `Build Maven` | Maven, JDK 17 | Définit la version de branche et compile. | Classes compilées | Oui | 92–98 |
| 3 | `Tests & couverture` | JUnit, Mockito, H2, JaCoCo | Lance les tests, construit le JAR testé et publie les rapports. | JAR + rapports tests/couverture | Oui | 100–114 |
| 4 | `Sécurité du code` (sous-stages parallèles) | Gitleaks, Trivy FS | Scanne l'historique et analyse les dépendances/IaC. | Rapport Gitleaks masqué, `trivy-fs.txt` | Gitleaks oui; Trivy rapport | 115–140 |
| 5 | `Analyse SonarQube` | SonarQube, JaCoCo | Analyse statique et couverture. | Résultat d'analyse | Oui | 141–155 |
| 6 | `Quality Gate` | SonarQube, webhook | Attend le verdict Quality Gate. | Verdict | Oui | 156–164 |
| 7 | `Publication JAR · Nexus` | Maven, Nexus | Publie le JAR validé, sauf PR. | Artefact Maven | Oui si déployé | 165–181 |
| 8 | `Image Docker` | Docker, JRE 17 Alpine | Emballe le JAR testé dans une image non-root. | Image Docker taguée | Oui si déployé | 182–196 |
| 9 | `Scan image · Trivy` | Trivy image | Scanne l'image avec `.trivyignore`; le mode strict bloque les CRITICAL corrigeables non acceptées. | Rapport Trivy | Rapport; strict sur `release/*`/`main` | 197–214 |
| 10 | `Push image · Amazon ECR` | AWS CLI, IAM, ECR | Publie via le rôle IAM de l'EC2. | Image stockée dans ECR | Oui si déployé | 215–228 |
| 11 | `Approbation production` | Jenkins `input` | Attend l'approbation avant promotion de `main`. | Approbation de release | Oui, `main` uniquement | 229–238 |
| 12 | `Promotion GitOps` | Git, GitHub | Clone `gitops` profondeur 20; écrit la config, rebase et pousse au plus 5 fois. | Commit SHA de déploiement | Oui si déployé | 239–297 |
| 13 | `Synchronisation Argo CD` | Argo CD CLI, Kubernetes | Attend le SHA dans `sync.revisions[]`, avec `Synced` et `Healthy`. | Confirmation du déploiement | Oui si déployé | 298–327 |
| 14 | `Tests post-déploiement` (sous-stages parallèles) | curl, Actuator, OWASP ZAP | Vérifie readiness/Prometheus et analyse passivement l'application. | Résultat des sondes et rapport ZAP | Actuator oui; ZAP selon branche | 328–365 |
| 15 | Notification de fin (bloc `post`) | Slack | Notifie le résultat du build. | Message `#igl5-g2-ci` | Non | 368–385 |
| 16 | Supervision continue (hors pipeline) | Prometheus, Alertmanager, Grafana | Scrape les métriques, alerte et affiche le dashboard. | Alertes et dashboards | Hors pipeline | `platform/gitops/platform/monitoring-config/` |

Les chemins et lignes correspondent à ce dépôt unique; l'étape 0 est créée par `platform/ansible/roles/github_webhook/` et le job Multibranch est configuré dans `platform/ansible/roles/devops_stack/templates/jenkins-casc.yaml.j2`. Schéma du flux : [docs/pipeline-devops.png](docs/pipeline-devops.png).

### Outils et configuration

| Outil | Rôle dans le projet | Fichiers de configuration |
|---|---|---|
| GitHub | Dépôt unique, branches, Pull Requests, webhook de build | `Jenkinsfile`; `platform/ansible/roles/github_webhook/tasks/main.yml`; `platform/ansible/roles/devops_stack/templates/jenkins-casc.yaml.j2` |
| GitFlow | Règles `feature/*`, `develop`, `release/*`, `main`; `gitops` dédiée à l'état de déploiement | `Jenkinsfile`, `platform/gitops/platform/apps/`, branche `gitops` |
| Jenkins | Multibranch, pipeline, JCasC, outils et identifiants | `Jenkinsfile`; `platform/ansible/roles/devops_stack/templates/jenkins-casc.yaml.j2`; `platform/ansible/roles/devops_stack/files/jenkins/` |
| Maven | Compilation, tests et publication du JAR | `pom.xml`, `ci/maven-settings.xml`, `Jenkinsfile` |
| JUnit | Tests Java automatisés | `pom.xml`, `src/test/java/` |
| Mockito | Isolation des tests unitaires | `pom.xml`, classes `*MockTest`/`*MockitoTest` |
| H2 | Base en mémoire des tests d'intégration | `pom.xml`, `src/test/resources/application.properties` |
| JaCoCo | Mesure et rapport de couverture | `pom.xml`, `Jenkinsfile`, `target/site/jacoco/` |
| Gitleaks | Recherche de secrets dans l'historique Git | `Jenkinsfile` |
| Trivy | Scan fichiers/IaC et image | `Jenkinsfile`, `.trivyignore` |
| SonarQube | Analyse statique et Quality Gate | `Jenkinsfile`; `platform/ansible/roles/sonar_config/tasks/main.yml` |
| Nexus | Dépôt de snapshots/releases Maven | `ci/maven-settings.xml`; `platform/ansible/roles/nexus_config/tasks/main.yml` |
| Docker | Image applicative et outils du build Jenkins | `Dockerfile`; `platform/ansible/roles/devops_stack/files/jenkins/Dockerfile` |
| Amazon ECR | Registre des images et scan à la réception | `Jenkinsfile`; `platform/terraform/ecr.tf` |
| Argo CD | Synchronisation GitOps dans EKS | `platform/terraform/argocd.tf`, `platform/terraform/values/argocd.yaml.tftpl`, `platform/gitops/platform/apps/` |
| Helm | Paramétrage des environnements de l'application | `platform/gitops/charts/events-app/` |
| Kubernetes EKS | Hébergement des namespaces et des workloads | `platform/terraform/eks.tf`, chart Helm et applications Argo CD |
| OWASP ZAP | DAST passif après déploiement | `Jenkinsfile` |
| Prometheus | Collecte et règles d'alerte | `platform/gitops/platform/apps/20-monitoring.yaml`, `platform/gitops/platform/monitoring-config/prometheus-rules.yaml` |
| Alertmanager | Routage Slack des alertes | `platform/gitops/platform/apps/20-monitoring.yaml`, `platform/terraform/argocd.tf` |
| Grafana | Dashboard par environnement; accès via port-forward | `platform/gitops/platform/monitoring-config/grafana-dashboard-configmap.yaml`, `platform/gitops/platform/apps/20-monitoring.yaml` |
| Slack | Notifications Jenkins, déploiements et incidents | JCasC, `platform/gitops/platform/apps/40-events-environments.yaml`, `platform/gitops/platform/apps/20-monitoring.yaml` |
| Terraform | Infrastructure AWS, EKS, ECR, Argo CD et passage Ansible | `platform/terraform/*.tf`, `platform/terraform/values/` |
| Ansible | Configuration de l'EC2 et des intégrations | `platform/ansible/site.yml`, `platform/ansible/roles/` |

### Webhooks et notifications

| Flux | Rôle / étape | Création ou configuration |
|---|---|---|
| GitHub → Jenkins | Déclenchement étape 0 pour push et Pull Request | Création idempotente : `platform/ansible/roles/github_webhook/tasks/main.yml`; URL : `platform/ansible/group_vars/devops/vars.yml`; job et réception : `platform/ansible/roles/devops_stack/templates/jenkins-casc.yaml.j2` |
| SonarQube → Jenkins | Retour Quality Gate à l'étape 6 | Création : `platform/ansible/roles/sonar_config/tasks/main.yml`; consommation : `Jenkinsfile` (`Quality Gate`) |
| Jenkins → Slack | Résultat de build à l'étape 15, canal `#igl5-g2-ci` | `Jenkinsfile` (`notifyTeam`); credential/canal : `platform/ansible/roles/devops_stack/templates/jenkins-casc.yaml.j2` |
| Argo CD → Slack | Événements de déploiement après l'étape 13 | Service/token : `platform/terraform/values/argocd.yaml.tftpl`; abonnements : `platform/gitops/platform/apps/40-events-environments.yaml` |
| Alertmanager → Slack | Alertes et résolutions de supervision continue, étape 16 | Secret webhook : `platform/terraform/argocd.tf`; receiver : `platform/gitops/platform/apps/20-monitoring.yaml` |

Les deux premiers sont des webhooks entrants. Le webhook GitHub cible `https://jenkins.<IP>.sslip.io/github-webhook/` (JSON, événements `push` et `pull_request`); le jeton Vault doit avoir les portées `repo` et `admin:repo_hook`. Jenkins et Argo CD notifient Slack via plugin/API; Alertmanager utilise un webhook Slack sortant.

### Tests et couverture

Chemins relatifs à `src/test/java/tn/fst/eventsproject/`. Chaque classe et son nombre de tests (résultat de `mvnw -B clean verify`) :

| Classe et chemin | Type | Ce qui est vérifié | Tests |
|---|---|---|---:|
| `controllers/EventStatsControllerMockTest.java` | Unitaire, Mockito | Réponses du contrôleur pour les statistiques d'événement, plages de dates et statistiques globales. | 5 |
| `controllers/LogisticsControllerMockTest.java` | Unitaire, Mockito | Routes CRUD logistique avec service simulé. | 4 |
| `controllers/LogisticsControllerTest.java` | Intégration Spring/H2 | Requêtes HTTP CRUD du contrôleur logistique. | 4 |
| `controllers/ParticipantRestControllerIntegrationTest.java` | Intégration Spring/H2 | CRUD participants, changement de tâche et réponses 404. | 6 |
| `controllers/ParticipantRestControllerMockitoTest.java` | Unitaire Mockito (Web MVC) | Sérialisation JSON, CRUD, tâche invalide et erreurs 404. | 8 |
| `services/EventServicesImplTest.java` | Intégration Spring/H2 | CRUD des événements avec le contexte Spring. | 4 |
| `services/EventServicesMockTest.java` | Unitaire, Mockito | CRUD événements et cas d'identifiant absent. | 5 |
| `services/EventStatsServiceImplIntegrationTest.java` | Intégration Spring/H2 | Calcul des statistiques événementielles et globales persistées. | 4 |
| `services/EventStatsServiceImplMockTest.java` | Unitaire, Mockito | Statistiques, cas vides/inconnus, tri et intervalle de dates invalide. | 9 |
| `services/LogisticsServiceImplMockTest.java` | Unitaire, Mockito | CRUD du service logistique avec repository simulé. | 4 |
| `services/LogisticsServiceImplTest.java` | Intégration Spring/H2 | CRUD logistique avec repositories réels en mémoire. | 4 |
| `services/ParticipantServicesImplIntegrationTest.java` | Intégration Spring/H2 | Persistance CRUD, changement de tâche et participant absent. | 7 |
| `services/ParticipantServicesImplMockitoTest.java` | Unitaire, Mockito | CRUD participants, sauvegarde, tâches et erreurs 404. | 9 |

Commande complète : `./mvnw -B clean verify` (73 tests, H2 pour l'intégration). Couverture HTML : `target/site/jacoco/index.html`; XML : `target/site/jacoco/jacoco.xml`.

### Lancer le pipeline sur sa feature

Depuis le dépôt applicatif, après avoir récupéré la branche `develop` à jour :

```bash
git switch develop
git pull --ff-only origin develop
git switch -c feature/ma-feature
./mvnw -B clean verify
git add . && git commit -m "feat: description de la feature" && git push -u origin feature/ma-feature
```

Le guide complet (backend Terraform, secrets, AWS, Ansible, GitOps, validations et suppression d'un environnement) se trouve dans [docs/GUIDE-EXECUTION.md](docs/GUIDE-EXECUTION.md).

## Sécurité

| Contrôle | Étape | Comportement |
|---|---|---|
| Gitleaks (historique complet) | 4a | Bloquant : aucun secret ne doit entrer dans Git. |
| Trivy FS (dépendances, IaC) | 4b | Rapport `trivy-fs.txt`. |
| SonarQube + Quality Gate | 5–6 | Bloquant. |
| Trivy image (`--severity CRITICAL --ignore-unfixed --ignorefile .trivyignore`) | 9 | Rapport sur `feature/*`/`develop`; **bloquant** (`--exit-code 1`) sur `release/*` et `main`. |
| OWASP ZAP (passif) | 14b | Rapport après déploiement. |

**Dépendances corrigées** : Spring Boot 2.7.6 → 2.7.18, SnakeYAML 2.2 (CVE-2022-1471), Tomcat 9.0.121 (7 CVE critiques). Avec ces mises à jour et l'acceptation de risque ci-dessous, le scan strict de l'image renvoie le code **0**.

### Acceptation de risque Trivy

Deux CVE critiques restent dans Spring Framework 5.3.31 (dernière ligne compatible Spring Boot 2.7). Leur correction exige Spring 6/7, donc Spring Boot 3+ (Java 17, migration `javax` → `jakarta`). Elles sont déclarées dans [`.trivyignore`](.trivyignore), archivé avec les rapports de chaque build :

| CVE | Composant | Classe vulnérable | Pourquoi l'application n'est pas exposée | Expiration |
|---|---|---|---|---|
| CVE-2016-1000027 | `spring-web` 5.3.31 | `HttpInvokerServiceExporter` (désérialisation Java) | Aucune utilisation de Spring Remoting/HttpInvoker dans `src/`; API REST JSON uniquement. | 2027-03-31 |
| CVE-2026-47884 | `spring-webmvc` 5.3.31 | `XsltView` (vues XSLT) | Aucune vue XSLT ni fichier `.xsl` dans `src/`; dashboard statique. | 2027-03-31 |

**Plan de correction** : migration vers Spring Boot 3 (amélioration n°1 du rapport), puis suppression des deux entrées de `.trivyignore`. Les entrées expirent le 31/03/2027 : après cette date, Trivy les signale de nouveau et le mode strict bloque `main` et `release/*`, ce qui impose une réévaluation. Si une nouvelle utilisation de ces classes apparaît dans le code, l'acceptation devient caduque.

## Structure du projet

```
IGL5-G2-EventsProjetcs
├── pom.xml
├── Jenkinsfile                             # pipeline CI/CD unique
├── Dockerfile
├── .trivyignore                            # acceptation de risque Trivy (expire 2027-03-31)
├── ci/maven-settings.xml
├── docs/
│   ├── dashboard.png
│   ├── architecture.png
│   ├── pipeline-devops.png
│   ├── GUIDE-EXECUTION.md
│   ├── RAPPORT-REALISATION.md
│   └── Rapport-DevOps-Events-FST-v4.pdf
├── platform/                              # Terraform, Ansible, Argo CD, Helm et exploitation
│   ├── Makefile                           # make help : cycle de vie complet
│   ├── terraform/                         # VPC, EKS, ECR, EC2 outillage, Argo CD
│   ├── ansible/                           # Jenkins (JCasC), Nexus, SonarQube, webhooks
│   ├── gitops/
│   │   ├── charts/events-app/             # chart Helm commun (profils review/staging/prod)
│   │   └── platform/                      # apps Argo CD, ApplicationSet, monitoring, gp3
│   └── scripts/                           # bootstrap-state, post-apply, destroy
└── src
    ├── main
    │   ├── java/tn/fst/eventsproject
    │   │   ├── EventsProjectApplication.java   # point d'entrée (@EnableScheduling)
    │   │   ├── config/
    │   │   │   ├── PerformanceAspect.java      # AOP : temps d'exécution des services
    │   │   │   ├── BusinessMetricsConfig.java  # métriques métier pour Prometheus
    │   │   │   └── DemoDataLoader.java         # données de démo (app.demo-data=true)
    │   │   ├── controllers/                    # API REST
    │   │   ├── dto/                            # EventStatsDTO, GlobalStatsDTO
    │   │   ├── entities/                       # Event, Participant, Logistics, Tache
    │   │   ├── repositories/                   # Spring Data JPA
    │   │   └── services/                       # interfaces + implémentations
    │   └── resources
    │       ├── application.properties          # MySQL, port 8089, context-path /events
    │       └── static/                         # dashboard (index.html, logo, Chart.js)
    └── test
        ├── java/tn/fst/eventsproject
        │   ├── controllers/
        │   └── services/
        └── resources/application.properties    # H2 en mémoire pour les tests
```

## Workflow Git

- `main` : branche stable; `develop` : intégration continue.
- `feature/<nom>` : une branche par fonctionnalité (ex. `feature/event-statistics`), fusionnée dans `develop` via une Pull Request.
- `release/<version>` : validation de version avant fusion dans `main`; `hotfix/<nom>` : correctif urgent destiné à `main`.
- `gitops` : branche orpheline réservée aux fichiers de déploiement `envs/<environnement>/{config.json,values.yaml}`. Elle ne contient pas de Jenkinsfile et est exclue du Multibranch pour empêcher une boucle de builds.

```bash
git checkout develop && git pull --ff-only origin develop
git checkout -b feature/ma-fonctionnalite
# ... développement + tests ...
./mvnw -B clean verify
git add -A
git commit -m "feat: description de la fonctionnalité"
git push -u origin feature/ma-fonctionnalite
# puis ouvrir une Pull Request vers develop
```

Convention des messages de commit : `feat:` (nouvelle fonctionnalité), `fix:` (correction), `test:` (tests), `docs:` (documentation), `refactor:` (restructuration).

## Dépannage

<details>
<summary><b><code>cannot find symbol: variable log</code> / <code>getXxx()</code> / <code>builder()</code> à la compilation</b></summary>

Lombok n'est pas exécuté. Le `pom.xml` déclare Lombok dans `annotationProcessorPaths` (obligatoire depuis le JDK 23) : vérifiez que vous utilisez bien la version à jour du `pom.xml`. Dans IntelliJ IDEA : *Settings → Build → Compiler → Annotation Processors → Enable annotation processing*, puis *Maven → Reload project*.
</details>

<details>
<summary><b><code>Communications link failure</code> au démarrage</b></summary>

MySQL n'est pas démarré ou n'écoute pas sur le port `3306`. Démarrez MySQL, ou vérifiez l'URL et les identifiants dans `application.properties`.
</details>

<details>
<summary><b>Le dashboard affiche « API injoignable »</b></summary>

L'application n'est pas lancée, ou le dashboard a été ouvert directement comme fichier. Ouvrez-le via le serveur : <http://localhost:8089/events/>.
</details>

<details>
<summary><b><code>Port 8089 was already in use</code></b></summary>

Une autre instance tourne déjà. Arrêtez-la, ou changez `server.port` dans `application.properties`.
</details>

---

<p align="center">
  <sub>Faculté des Sciences de Tunis · Université de Tunis El Manar · IGL5 — Groupe 2</sub>
</p>
