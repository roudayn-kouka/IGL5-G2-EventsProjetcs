# Feedback ? ?tat final de la cha?ne DevOps

Relev? du **29 octobre 2026**, fuseau **Africa/Tunis (UTC+1)**. Branche applicative **feature/feedback**, commit **104b0ca3b4389bdb86b6df0dee28c169456df3ae**. Ce relev? actualise l??tat d?ex?cution d?crit dans le dossier de pr?sentation ant?rieur ; le dossier modifi? par l?utilisateur a ?t? conserv?.

**Build de r?f?rence : [Jenkins #12](http://localhost:8083/job/Events-DevOps/job/feature%252Ffeedback/12/). La cha?ne compl?te n?est pas d?montr?e verte : ZAP non ex?cut?, arr?t du build demand?, r?sultat final Jenkins non r?cup?rable.** Un seul build Feedback complet a ?t? lanc? ; **aucune relance**. L?utilisateur a demand? de s?arr?ter et de documenter le blocage. Le premier t?l?chargement de ZAP repr?sente environ **1,206 Go compress?**, dont une couche de 626 Mo ; son extraction locale s?est bloqu?e apr?s le d?ploiement r?ussi. Un diagnostic s?par? `Feedback-connection-check #1` a v?rifi? les credentials via les bindings Jenkins, sans build applicatif : [journal](evidence/feedback-pipeline-build-12/preflight.log).

## Identifiants et d?ploiement v?rifi?s

| ?l?ment | Valeur prouv?e |
|---|---|
| Image ECR | `471112616916.dkr.ecr.us-east-1.amazonaws.com/events-app:feedback-12-104b0ca` |
| Digest ECR et image r?ellement ex?cut?e | `sha256:5182b814ce262bf1eab1fba12ac0969bcb2398684ea6382f4002901b8ce5345e` |
| Commit de promotion GitOps | `025375385b2c957d2f28d09e8c0c0abc5026ccb3` |
| Application / namespace | `events-feedback` / `events-feedback` |
| Argo CD | **Synced / Healthy**, r?vision exacte du commit GitOps ci-dessus, aucune condition d?erreur |
| Application et MySQL | **1/1 Ready chacun**, z?ro red?marrage au relev? du **29/10 ? 22:23 +01:00** |
| Workers EKS | **Deux Ready**, capacit? et nombre inchang?s |
| URL de d?monstration | [Feedback sur EKS](http://feedback.44.218.144.91.sslip.io/events/) |
| Prometheus | `up{job="events-app",namespace="events-feedback"} = 1` |

Sources : [AWS ECR](evidence/feedback-pipeline-build-12/ecr-image-12.json), [d?ploiement Kubernetes/Argo](evidence/feedback-pipeline-build-12/deployment.json), [promotion et chemins modifi?s](evidence/feedback-pipeline-build-12/gitops-changes.json), [requ?te Prometheus r?elle](evidence/feedback-pipeline-build-12/prometheus-feedback-up.json). L?URL utilise une adresse actuelle du load balancer existant via sslip.io ; elle est temporaire et en HTTP.

## Stages ex?cut?s dans #12

| Stage | R?sultat r?el / limite |
|---|---|
| GitFlow et checkout | `feature/feedback`, commit `104b0ca`, tag et namespace Feedback corrects |
| Build Maven | R?ussi |
| JUnit et JaCoCo | **125 tests, 0 ?chec, 0 erreur, 0 ignor?**, rapport de couverture publi? |
| Gitleaks | Termin?, **0 fuite d?tect?e** dans son p?rim?tre |
| Trivy filesystem / IaC | Termin? en mode `report` existant : **15 findings, 13 HIGH / 2 CRITICAL** ; erreurs de compatibilit? Rego, certaines r?gles ignor?es |
| SonarQube | Analyse termin?e ; t?che `fe6163de-f97b-4881-a97c-a020c94990d5` |
| Quality Gate | **OK** |
| Nexus | Publication **SNAPSHOT r?ussie**, `tn.fst:eventsProject:1.0.0-feedback-SNAPSHOT` ; aucune RELEASE ex?cut?e |
| Docker | Image construite avec le vrai registre ECR, puis scann?e |
| Trivy image | Termin? en mode `report` existant : **1 CRITICAL**, r?sultat non vierge |
| ECR | STS et repository v?rifi?s avec le Secret file Academy ; login, push et nettoyage Docker r?ussis |
| Approbation production | Ignor?e normalement : cette branche n?est pas `main` |
| Promotion GitOps | Push r?el r?ussi avec **events-github-read**, historique existant conserv? ; **17 chemins, tous sous envs/feedback/** |
| Synchronisation Argo | Jenkins a v?rifi? **commit-attendu=true, Synced, Healthy** |
| Smoke tests Jenkins | Readiness **UP**, endpoint Prometheus disponible, r?sum? statistique **200** ; `/events/event/` retourne **404** et reste un avertissement du pipeline existant |
| OWASP ZAP | **Non ex?cut? / non d?montr?** : extraction de l?image bloqu?e ; aucun verdict de scan disponible. Le stage a ?t? atteint, ce qui ne prouve pas qu?un scan a eu lieu. |

Appuis directs : tests [J12:L668](evidence/feedback-pipeline-build-12/jenkins-12.log#L668), gate [J12:L1195](evidence/feedback-pipeline-build-12/jenkins-12.log#L1195), Nexus [J12:L1255](evidence/feedback-pipeline-build-12/jenkins-12.log#L1255), push [J12:L1463](evidence/feedback-pipeline-build-12/jenkins-12.log#L1463), Argo voir journal J12. Rapports existants copi?s : [Gitleaks](evidence/feedback-pipeline-build-12/gitleaks-report.json), [Trivy FS](evidence/feedback-pipeline-build-12/trivy-fs.txt), [Trivy image](evidence/feedback-pipeline-build-12/trivy-image.txt), [m?tadonn?es Sonar](evidence/feedback-pipeline-build-12/sonar-analysis-task-build-12.txt). Un gate OK et des stages en mode report ne prouvent pas l?absence de vuln?rabilit?s.

## Corrections effectivement apport?es

1. **Credential GitHub absent :** pour Feedback, le stage utilise le credential existant `events-github-read`. Le diagnostic a v?rifi? son droit push avec l?API GitHub ; le push GitOps r?el de #12 le d?montre ensuite. Aucun credential local Git n?a servi de preuve de ce droit. [Jenkinsfile:306](../Jenkinsfile#L306)
2. **Risque de fuite de l?en-t?te Basic :** `set +x` pr?c?de la lecture du credential GitHub et la cr?ation de l?en-t?te encod?. `set -eu`, garde de branche `gitops`, contr?le namespace et contr?le des chemins index?s prot?gent la promotion Feedback. L?URL distante reste sans token. [Jenkinsfile:311](../Jenkinsfile#L311)
3. **Rendu Argo multi-r?vision du m?me d?p?t :** une [ComparisonError observ?e](evidence/feedback-pipeline-build-12/argo-rendering-diagnostic.txt) r?v?lait que cette version ne peut pas rendre chart et valeurs issus de deux r?visions du m?me d?p?t. Feedback promeut donc une copie du chart examin? et son commit source dans `envs/feedback/`, avec les valeurs runtime ; l?ApplicationSet utilise une seule r?vision GitOps, **uniquement pour Feedback**. Les sources des autres environnements sont conserv?es. [Jenkinsfile:327](../Jenkinsfile#L327) [ApplicationSet:70](../platform/gitops/platform/apps/40-events-environments.yaml#L70). Cette restriction est aussi explicite dans le [code officiel Argo CD](https://github.com/argoproj/argo-cd/blob/master/reposerver/repository/repository.go) et le [ticket officiel #25605](https://github.com/argoproj/argo-cd/issues/25605).
4. **Authentification Argo manquante :** compte d?di? `jenkins-feedback`, token valable **24 h**, stock? comme Secret text Jenkins `argocd-token`. Droits : `applications,get,events/events-feedback` et `projects,get,events`. Ce dernier droit s?est r?v?l? n?cessaire au CLI apr?s le premier d?ploiement ; ajout? pendant l?attente du m?me build, sans relance. Aucun droit sync/admin accord? au nouveau compte. [Diagnostic RBAC expurg?](evidence/feedback-pipeline-build-12/argo-rbac-diagnostic.log)
5. **Acc?s priv? et configuration Jenkins :** helper local `events-argocd-tunnel`, r?seau Docker `jenkins-net`, **aucun port h?te publi?**. Les credentials Academy du tunnel ne contiennent que le profil default et restent hors d?p?t. Param?tres du seul job Feedback : `PLATFORM_REPO=roudayn-kouka/IGL5-G2-EventsProjetcs`, `GITOPS_BRANCH=gitops`, `ARGOCD_SERVER=events-argocd-tunnel:8080`, `APPS_DOMAIN=44.218.144.91.sslip.io`. R?gion et registre globaux ?taient d?j? corrects.
6. **Suivi de la r?vision :** le contr?le Argo accepte les champs `status.sync.revisions` ou `status.sync.revision`, en conservant l?exigence du commit GitOps exact et de l??tat Synced/Healthy. [Jenkinsfile:392](../Jenkinsfile#L392)

Seuls `Jenkinsfile` et l?ApplicationSet ont ?t? commit?s/pouss?s sur `feature/feedback` (`104b0ca`). Aucun code m?tier, test, gate, Terraform, ?tat, `main` ou `develop` n?a ?t? ?crit par ces op?rations. La copie du chart dans GitOps facilite la reproductibilit? de Feedback ; une modification future du chart applicatif exige une nouvelle promotion. **Le remote main a avanc? pendant la collecte, hors des pushes effectu?s ici ; il n?a pas ?t? r?initialis? ni remplac?.** Le main local est rest? `32a32c3`. [Relev? des refs](evidence/feedback-pipeline-build-12/branch-heads.json)

## Blocage final et d?cision d?arr?t

- L?image ZAP a commenc? ? ?tre t?l?charg?e ? **22:22 +01:00** ; derni?re progression conserv?e dans le journal ? **22:32:39 +01:00**, puis absence de progression pendant les v?rifications suivantes.
- Windows ne disposait initialement que d?environ **1 Go libre sur C:**, alors que `df` dans la VM Docker annon?ait beaucoup d?espace. L?utilisateur a lib?r? de l?espace ; les lectures suivantes ont mesur? environ **3 ? 3,2 Go**. Docker n?a pas repris pendant les observations. Les logs consult?s ne montrent **pas d?erreur ENOSPC explicite** : le faible espace est un facteur probable, pas une cause d?finitivement prouv?e. La RAM physique libre relev?e ?tait d?environ 3,37 Go sur 32,48 Go.
- Une commande locale `docker stats` restait sans r?ponse ; apr?s la demande d?arr?t, une lecture de statut Jenkins a elle aussi expir? apr?s **10 secondes**. Aucun red?marrage de Docker, aucun nettoyage d?images/fichiers sans rapport et aucune augmentation de ressources n?ont ?t? ex?cut?s.
- La requ?te normale d?arr?t de **#12** a ?t? accept?e par Jenkins vers **22:42 +01:00**. Sa terminaison n?a pas pu ?tre confirm?e : **ne pas ?crire SUCCESS, FAILURE ou ABORTED comme r?sultat final constat?**. Le dernier r?sultat API sauvegard? indique `building=true`, `result=null` ; il pr?c?de la demande d?arr?t. La capture Jenkins montre ?galement un build encore en cours.
- L?utilisateur a choisi **? Stop here and document the blocker ?**, plut?t que le red?marrage global de Docker Desktop qui aurait interrompu les autres conteneurs locaux. Aucune seconde ex?cution Feedback compl?te n?a donc ?t? lanc?e. Le diagnostic Argo `Feedback-connection-check #2`, planifi? pendant l?attente, ?tait en file au dernier relev? ; son r?sultat n?est pas utilis? comme preuve. La tentative d?annulation de ce diagnostic a ?galement expir? ; [annulation non confirm?e](evidence/feedback-pipeline-build-12/diagnostic-cancellation.json).

Preuves : [dernier journal Jenkins](evidence/feedback-pipeline-build-12/jenkins-12.log), [dernier statut connu](evidence/feedback-pipeline-build-12/jenkins-12.json), [chronologie et arr?t](evidence/feedback-pipeline-build-12/stop-status.json), [espace disque](evidence/feedback-pipeline-build-12/local-disk-observation.json), [diagnostic Docker filtr?](evidence/feedback-pipeline-build-12/docker-unpack-diagnostic.json). Les fichiers de statut et la capture sont des instantan?s dat?s, pas une garantie d??tat apr?s l?arr?t.

## V?rification m?tier suppl?mentaire ? hors pipeline

Un test r?el sur **MySQL dans EKS** a utilis? un couple ?v?nement termin? / participant d?j? associ? dans les donn?es de d?monstration : cr?ation **201**, doublon **409**, note JSON `5.0` **400**, consultation **200**, moyenne **200** et conforme aux notes, suppression **204**. Seul l?avis de v?rification a ?t? cr??, puis retir? ; aucune donn?e Event/Participant n?a ?t? modifi?e. [Requ?tes et r?ponses r?elles](evidence/feedback-pipeline-build-12/feedback-live-smoke.json)

Ce test compl?te les smoke tests g?n?riques de Jenkins ; il ne remplace pas un test concurrent multi-requ?te sur MySQL. La moyenne REST n?est toujours pas une m?trique m?tier Prometheus d?di?e.

## Preuves conserv?es et limites

R?pertoire local : **[docs/evidence/feedback-pipeline-build-12](evidence/feedback-pipeline-build-12/)**. Copie hors de `target`, pr?serv?e par `mvn clean`. Ces nouvelles preuves et ce rapport restent locaux, non commit?s ; les `.log` et rapports de scan suivent les r?gles d?exclusion Git existantes. Exporter le dossier complet avant le nettoyage de l?environnement de d?monstration.

- [Journal complet #12](evidence/feedback-pipeline-build-12/jenkins-12.log), [r?sultat API](evidence/feedback-pipeline-build-12/jenkins-12.json), [graphe d?ex?cution](evidence/feedback-pipeline-build-12/jenkins-12-flow.json), [validations](evidence/feedback-pipeline-build-12/validation.txt).
- [Capture r?elle Jenkins](evidence/feedback-pipeline-build-12/jenkins-12.png) et [capture r?elle du dashboard applicatif d?ploy?](evidence/feedback-pipeline-build-12/feedback-application.png). Le dashboard est commun ; la colonne de moyenne est l?int?gration Feedback, pas une attribution individuelle des autres fonctionnalit?s.
- ?tat des pods de plateforme existants : [platform-pods.json](evidence/feedback-pipeline-build-12/platform-pods.json). Pas de capture Grafana authentifi?e ni de m?trique Sonar num?rique invent?e.

Limites persistantes : image Trivy avec CRITICAL et alertes IaC ; version du scanner incompatible avec certaines r?gles ; scans feature en mode report inchang? ; API de d?monstration sans authentification ni TLS applicatif ; MySQL review en `emptyDir`, donc avis non durables apr?s remplacement du pod. Les credentials Jenkins existants sont de port?e GLOBAL : la condition de branche ne cloisonne pas les builds hostiles. L?isolation des jobs/folders, agents et daemons Docker de confiance reste ? imposer avant d?admettre des branches non fiables ; elle n?est pas d?montr?e ici. Le token Argo expire apr?s 24 h et les credentials Academy/tunnel n?cessitent renouvellement apr?s expiration de session. Le compte/RBAC Argo et les param?tres Jenkins ont ?t? configur?s en direct ; aucun apply Terraform de p?rennisation n?a ?t? lanc?. Le dernier ?tat du helper priv? n?a pas pu ?tre rev?rifi? apr?s le blocage Docker.

## Destruction : pr?te ? ?tre revue, non ex?cut?e

**Aucun apply/destroy Terraform, changement de capacit? ou nouvelle infrastructure AWS facturable n?a ?t? ex?cut?.** Les workloads Feedback et l?image utilisent l?EKS, les deux workers, le load balancer et l?ECR existants. Le cluster, la NAT, les n?uds, volumes et le load balancer restent facturables tant que l?utilisateur n?effectue pas le nettoyage.

Apr?s export des preuves, arr?ter les nouveaux builds/promotions puis ex?cuter depuis `C:\IGL5-G2-EventsProjetcs` :

```powershell
.\platform\scripts\academy.ps1 -Action PreviewDestroy
# Examiner le plan et confirmer que le p?rim?tre est bien la plateforme partag?e voulue.
.\platform\scripts\academy.ps1 -Action Destroy
.\platform\scripts\academy.ps1 -Action Verify
```

Le script exige les confirmations `DESTROY fst-events 471112616916`, puis `APPLY DESTROY`, nettoie les objets GitOps/LB avant le plan final et conserve le backend S3. La configuration locale actuelle autorise la suppression des images ECR (`ecr_force_delete=true`) : exporter les preuves/digests avant confirmation. La destruction toucherait **la plateforme partag?e et tous ses environnements**, pas Feedback seul. **Pr?requis suppl?mentaire : confirmer l?arr?t effectif du build #12 et annuler le diagnostic en file lorsque Jenkins redeviendra accessible**, pour ?viter une reprise pendant le nettoyage. Pr?server les fichiers backend/tfvars/?tat ; les plans peuvent contenir des secrets et ne doivent pas ?tre archiv?s avec les preuves. Apr?s nettoyage, arr?ter le helper local avec `docker stop events-argocd-tunnel` et retirer sa copie temporaire de credentials. [academy.ps1:67](../platform/scripts/academy.ps1#L67) [academy.ps1:79](../platform/scripts/academy.ps1#L79)

**PreviewDestroy, Destroy et Verify n?ont pas ?t? ex?cut?s pour ce relev? ; la r?ussite d?un futur teardown reste ? v?rifier par l?utilisateur.**
