// =============================================================================
//  Events Project · FST · IGL5 G2 — Pipeline CI/CD/DevSecOps (GitOps)
//
//  UN SEUL Jenkinsfile pour TOUTES les branches (job Jenkins « Multibranch Pipeline »).
//    Jenkins  = intégration continue + sécurité + publication + PROMOTION GitOps
//    Argo CD  = déploiement (modèle « pull ») : il lit le dépôt plateforme et applique sur EKS
//  => Jenkins n'a AUCUN accès au cluster Kubernetes.
//
//  Contexte déduit du nom de branche (GitFlow) :
//    feature/<nom>  -> environnement éphémère events-<nom> (déployé seulement si le message
//                      du dernier commit contient [deploy], pour maîtriser les coûts AWS)
//    develop        -> events-staging (+ nettoyage des environnements éphémères orphelins)
//    release/x.y.z  -> events-staging (gate sécurité strict)
//    main           -> events-prod    (gate strict)
//    PR-*           -> intégration continue seulement
//
//  Variables globales (JCasC) : NEXUS_URL, ECR_REGISTRY, AWS_REGION, PLATFORM_REPO,
//                               GITOPS_BRANCH, ARGOCD_SERVER, APPS_DOMAIN
//  Credentials : nexus-credentials, github-credentials, dockerhub-credentials, argocd-token,
//                sonar-token (serveur « sonarqube »), aws-access-key-id,
//                aws-secret-access-key, aws-session-token
// =============================================================================

pipeline {
    agent any

    options {
        timestamps()
        ansiColor('xterm')
        timeout(time: 45, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '15', artifactNumToKeepStr: '5'))
        disableConcurrentBuilds()
    }

    environment {
        APP_NAME       = 'events-app'
        TRIVY_IMAGE    = 'aquasec/trivy:0.56.2'
        GITLEAKS_IMG   = 'zricethezav/gitleaks:v8.21.2'
        SONAR_PLUGIN   = 'org.sonarsource.scanner.maven:sonar-maven-plugin:3.11.0.3922'
        MVN            = 'mvn -B -ntp'
        ARGOCD_OPTS    = '--grpc-web --plaintext'
        DOCKERHUB_REPO = 'nour1mustapha/events-app'   // <-- À ADAPTER
        MAIL_TO        = 'your-team@example.com'          // <-- À ADAPTER
        PLATFORM_REPO = 'nm727/fst-events-platform'
        GITOPS_BRANCH = 'main'
    }

    stages {

        // ------------------------------------------------------------ 1
        stage('Contexte & garde GitFlow') {
            steps {
                script {
                    def branch = env.CHANGE_BRANCH ?: env.BRANCH_NAME
                    if (!(branch ==~ /^(main|develop|feature\/[a-z0-9-]+|release\/\d+\.\d+(\.\d+)?|hotfix\/[a-z0-9.-]+)$/)) {
                        error "Nom de branche '${branch}' hors convention GitFlow (feature/<nom-en-minuscules>, release/x.y.z, hotfix/...)"
                    }
                    if (env.CHANGE_ID && branch.startsWith('feature/') && env.CHANGE_TARGET != 'develop') {
                        error "GitFlow : une feature se fusionne dans develop, pas dans ${env.CHANGE_TARGET}"
                    }

                    env.BRANCH_TYPE   = env.CHANGE_ID ? 'pr' : branchType(branch)
                    env.FEATURE_SLUG  = featureSlug(branch)
                    env.OWNER         = ownerOf(branch)
                    env.OWNER_SLUG    = slugify(env.OWNER)
                    env.GIT_SHORT     = sh(script: 'git rev-parse --short=7 HEAD', returnStdout: true).trim()
                    env.K8S_NAMESPACE = namespaceFor(env.BRANCH_TYPE, env.FEATURE_SLUG)
                    env.ENV_NAME      = env.K8S_NAMESPACE.replaceFirst(/^events-/, '')
                    env.HELM_PROFILE  = profileFor(env.BRANCH_TYPE)
                    env.DEPLOY        = (env.BRANCH_TYPE == 'pr') ? 'false' : 'true'
                    env.SECURITY_GATE = (env.BRANCH_TYPE in ['main', 'release']) ? 'strict' : 'report'
                    env.APP_VERSION   = (env.BRANCH_TYPE == 'main') ? "1.0.${env.BUILD_NUMBER}" : "1.0.0-${env.FEATURE_SLUG}-SNAPSHOT"
                    env.IMAGE_TAG     = "${env.FEATURE_SLUG}-${env.BUILD_NUMBER}-${env.GIT_SHORT}"
                    env.IMAGE         = "${env.ECR_REGISTRY ?: 'registry.local'}/${env.APP_NAME}:${env.IMAGE_TAG}"
                    env.SONAR_KEY     = "fst-events-${env.FEATURE_SLUG}"
                    env.APP_HOST      = "${env.ENV_NAME}.${env.APPS_DOMAIN ?: 'apps.local'}"

                    currentBuild.displayName = "#${env.BUILD_NUMBER} · ${env.FEATURE_SLUG}"
                    currentBuild.description = "${env.OWNER} · ${env.GIT_SHORT} · ${env.K8S_NAMESPACE}"

                    echo """
                    ┌──────────────────────── Contexte ────────────────────────
                    │ Branche        : ${branch}  (${env.BRANCH_TYPE})
                    │ Responsable    : ${env.OWNER}
                    │ Version Maven  : ${env.APP_VERSION}
                    │ Image          : ${env.IMAGE}
                    │ Projet Sonar   : ${env.SONAR_KEY}
                    │ Environnement  : ${env.K8S_NAMESPACE}  (profil ${env.HELM_PROFILE})
                    │ URL            : http://${env.APP_HOST}/events/
                    │ Gate sécurité  : ${env.SECURITY_GATE}
                    └──────────────────────────────────────────────────────────"""
                }
            }
        }

        // ------------------------------------------------------------ 2
        stage('Build Maven') {
            steps {
                sh "${MVN} versions:set -DnewVersion=${APP_VERSION} -DgenerateBackupPoms=false"
                sh "${MVN} clean compile"
            }
        }

        // ------------------------------------------------------------ 3
        stage('Tests & couverture') {
            steps {
                sh "${MVN} verify"
            }
            post {
                always {
                    junit allowEmptyResults: true, testResults: 'target/surefire-reports/*.xml'
                    recordCoverage(tools: [[parser: 'JACOCO', pattern: 'target/site/jacoco/jacoco.xml']],
                                   id: 'jacoco', name: 'Couverture JaCoCo')
                }
            }
        }

        // ------------------------------------------------------------ 4
        stage('Sécurité du code') {
            parallel {
                stage('Secrets · Gitleaks') {
                    steps {
                        sh '''
                        docker run --rm --volumes-from jenkins $GITLEAKS_IMG detect \
                            --source "$WORKSPACE" --redact --no-banner \
                            --report-format json --report-path "$WORKSPACE/gitleaks-report.json"
                        '''
                    }
                }
                stage('Dépendances & IaC · Trivy FS') {
                    steps {
                        sh '''
                        docker run --rm --volumes-from jenkins -v trivy-cache:/root/.cache $TRIVY_IMAGE fs \
                            --scanners vuln,misconfig --severity HIGH,CRITICAL --exit-code 0 \
                            --skip-db-update \
                            --format table --output "$WORKSPACE/trivy-fs.txt" "$WORKSPACE"
                        cat trivy-fs.txt
                        '''
                    }
                }
            }
        }

        // ------------------------------------------------------------ 5
        stage('Analyse SonarQube') {
            steps {
                withSonarQubeEnv('sonarqube') {
                    sh """
                      ${MVN} ${SONAR_PLUGIN}:sonar \
                        -Dsonar.projectKey=${SONAR_KEY} \
                        -Dsonar.projectName='Events · ${FEATURE_SLUG}' \
                        -Dsonar.projectVersion=${APP_VERSION} \
                        -Dsonar.coverage.jacoco.xmlReportPaths=target/site/jacoco/jacoco.xml
                    """
                }
            }
        }

        // ------------------------------------------------------------ 6
        stage('Quality Gate') {
            steps {
                timeout(time: 10, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        // ------------------------------------------------------------ 7
        stage('Publication JAR · Nexus') {
            when { expression { env.DEPLOY == 'true' } }
            steps {
                script {
                    def repo = env.APP_VERSION.endsWith('-SNAPSHOT') ? 'maven-snapshots' : 'maven-releases'
                    withCredentials([usernamePassword(credentialsId: 'nexus-credentials',
                                                      usernameVariable: 'NEXUS_USR', passwordVariable: 'NEXUS_PSW')]) {
                        sh """
                          ${MVN} -s ci/maven-settings.xml deploy -DskipTests \
                            -DaltDeploymentRepository=nexus::default::${env.NEXUS_URL}/repository/${repo}/
                        """
                    }
                }
            }
        }

        // ------------------------------------------------------------ 8
        stage('Image Docker') {
            when { expression { env.DEPLOY == 'true' } }
            steps {
                sh '''
                  docker build --pull \
                    --label org.opencontainers.image.revision=$GIT_SHORT \
                    --label org.opencontainers.image.version=$APP_VERSION \
                    --label tn.fst.feature=$FEATURE_SLUG \
                    --label tn.fst.owner=$OWNER_SLUG \
                    -t $IMAGE .
                '''
            }
        }

        // ------------------------------------------------------------ 9
        stage('Scan image · Trivy') {
            when { expression { env.DEPLOY == 'true' } }
            steps {
                script {
                    def exitCode = (env.SECURITY_GATE == 'strict') ? '1' : '0'
                    sh """
                    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                        --volumes-from jenkins -v trivy-cache:/root/.cache ${TRIVY_IMAGE} image \
                        --skip-db-update --skip-java-db-update \
                        --severity CRITICAL --ignore-unfixed --exit-code ${exitCode} \
                        --ignorefile "\$WORKSPACE/.trivyignore" \
                        --format table --output "\$WORKSPACE/trivy-image.txt" ${IMAGE}
                    """
                    sh 'cat trivy-image.txt'
                }
            }
        }

        // ------------------------------------------------------------ 10
        stage('Push image · Amazon ECR') {
            when { expression { env.DEPLOY == 'true' } }
            steps {
                withCredentials([
                    string(credentialsId: 'aws-access-key-id',     variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'aws-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY'),
                    string(credentialsId: 'aws-session-token',     variable: 'AWS_SESSION_TOKEN')
                ]) {
                    sh '''
                    docker run --rm -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN \
                        amazon/aws-cli ecr get-login-password --region "$AWS_REGION" \
                        | docker login --username AWS --password-stdin "$ECR_REGISTRY"
                    docker push "$IMAGE"
                    docker logout "$ECR_REGISTRY"
                    '''
                }
            }
        }

        // ------------------------------------------------------------ 11  (NOUVEAU)
        stage('Push image · Docker Hub') {
            when { expression { env.DEPLOY == 'true' } }
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub-credentials',
                                                  usernameVariable: 'DH_USR', passwordVariable: 'DH_PSW')]) {
                    sh '''
                      echo "$DH_PSW" | docker login -u "$DH_USR" --password-stdin
                      docker tag "$IMAGE" "$DOCKERHUB_REPO:$IMAGE_TAG"
                      docker push "$DOCKERHUB_REPO:$IMAGE_TAG"
                      docker logout
                    '''
                }
            }
        }

        // ------------------------------------------------------------ 12  (NOUVEAU)
        stage('Terraform · validate') {
            when { expression { fileExists('terraform') } }   // adapter le nom du dossier
            steps {
                sh '''
                  TF="docker run --rm --volumes-from jenkins -w $WORKSPACE/terraform hashicorp/terraform:1.9"
                  $TF fmt -check -recursive
                  $TF init -backend=false
                  $TF validate
                '''
            }
        }

        // ------------------------------------------------------------ 13  (NOUVEAU)
        stage('Décision de déploiement') {
            when { expression { env.DEPLOY == 'true' } }
            steps {
                script {
                    def msg = sh(script: 'git log -1 --pretty=%B', returnStdout: true)
                    env.DO_DEPLOY = (env.BRANCH_TYPE != 'feature' || msg.contains('[deploy]')) ? 'true' : 'false'
                    echo "Déploiement Kubernetes : ${env.DO_DEPLOY}  (feature : ajouter [deploy] au message de commit)"
                }
            }
        }

        // ------------------------------------------------------------ 14
        stage('Promotion GitOps') {
            when { expression { env.DO_DEPLOY == 'true' } }
            steps {
                withCredentials([usernamePassword(credentialsId: 'github-credentials',
                                                  usernameVariable: 'GIT_USER', passwordVariable: 'GIT_TOKEN')]) {
                    sh '''
                      rm -rf gitops-work
                      AUTH_HEADER="AUTHORIZATION: basic $(printf '%s' "$GIT_USER:$GIT_TOKEN" | base64 | tr -d '\n')"
                      git -c http.extraheader="$AUTH_HEADER" \
                        clone --branch "$GITOPS_BRANCH" --depth 20 "https://github.com/$PLATFORM_REPO.git" gitops-work
                      trap 'cd "$WORKSPACE"; rm -rf gitops-work' EXIT
                      git -C gitops-work config http.extraheader "$AUTH_HEADER"
                      unset AUTH_HEADER
                      ENV_DIR="gitops-work/envs/$ENV_NAME"
                      mkdir -p "$ENV_DIR"

                      cat > "$ENV_DIR/config.json" <<EOF
{ "namespace": "$K8S_NAMESPACE", "profile": "$HELM_PROFILE", "owner": "$OWNER_SLUG" }
EOF
                      cat > "$ENV_DIR/values.yaml" <<EOF
# Généré par Jenkins — build #$BUILD_NUMBER — commit $GIT_SHORT — ne pas modifier à la main
feature: $FEATURE_SLUG
owner: $OWNER_SLUG
image:
  repository: $DOCKERHUB_REPO
  tag: $IMAGE_TAG
ingress:
  host: $APP_HOST
EOF
                      cd gitops-work
                      git config user.name  "Jenkins FST"
                      git config user.email "jenkins@fst-events.local"
                      git add "envs/$ENV_NAME"
                      git diff --cached --quiet || git commit -m "deploy($ENV_NAME): $IMAGE_TAG [build #$BUILD_NUMBER · $OWNER]"

                      PUSHED=false
                      for i in 1 2 3 4 5; do
                        if git push origin "HEAD:$GITOPS_BRANCH"; then
                          PUSHED=true
                          break
                        fi
                        if [ "$i" -lt 5 ]; then
                          git pull --rebase origin "$GITOPS_BRANCH"
                        fi
                      done
                      if [ "$PUSHED" != true ]; then
                        echo "Échec du push GitOps après cinq tentatives."
                        exit 1
                      fi
                      git rev-parse HEAD > ../gitops-revision.txt
                    '''
                }
            }
        }

        // ------------------------------------------------------------ 15
        stage('Synchronisation Argo CD') {
            when { expression { env.DO_DEPLOY == 'true' } }
            steps {
                withCredentials([string(credentialsId: 'argocd-token', variable: 'ARGOCD_AUTH_TOKEN')]) {
                    sh '''
                      APP="events-$ENV_NAME"
                      WANTED=$(cat gitops-revision.txt)
                      for i in $(seq 1 60); do
                        J=$(argocd app get "$APP" --refresh -o json 2>/dev/null || true)
                        REV=$(echo "$J" | jq -r '(.status.sync.revisions // []) | join(",")')
                        REV_MATCH=$(echo "$J" | jq -r --arg wanted "$WANTED" '(.status.sync.revisions // []) | index($wanted) != null')
                        SYNC=$(echo "$J" | jq -r '.status.sync.status // empty')
                        HEALTH=$(echo "$J" | jq -r '.status.health.status // empty')
                        echo "[$i] $APP révisions=$REV commit-attendu=$REV_MATCH sync=$SYNC santé=$HEALTH"
                        if [ "$REV_MATCH" = "true" ] && [ "$SYNC" = "Synced" ] && [ "$HEALTH" = "Healthy" ]; then
                          echo "Déployé et sain."; exit 0
                        fi
                        if [ "$REV_MATCH" = "true" ] && [ "$HEALTH" = "Degraded" ]; then
                          echo "Déploiement dégradé : voir l'interface Argo CD."; exit 1
                        fi
                        sleep 10
                      done
                      echo "Délai dépassé (10 min)."; exit 1
                    '''
                }
            }
        }

        // ------------------------------------------------------------ 16
        stage('Smoke tests') {
            when { expression { env.DO_DEPLOY == 'true' } }
            steps {
                sh '''
                  BASE="http://$APP_HOST/events"
                  HEALTH=$(curl -fsS --retry 10 --retry-delay 6 --retry-all-errors "$BASE/actuator/health/readiness")
                  echo "$HEALTH"
                  echo "$HEALTH" | grep -Eq '"status"[[:space:]]*:[[:space:]]*"UP"' || {
                    echo "Readiness Actuator n'est pas UP."; exit 1;
                  }
                  curl -fsS --retry 10 --retry-delay 6 --retry-all-errors -o /dev/null "$BASE/actuator/prometheus"
                  echo "Endpoint Prometheus disponible."

                  for endpoint in "$BASE/event-stats/summary" "$BASE/event/"; do
                    STATUS=$(curl -sS -o /dev/null -w '%{http_code}' "$endpoint" || true)
                    if [ "$STATUS" = "404" ]; then
                      echo "AVERTISSEMENT : endpoint métier absent sur cette feature : $endpoint"
                    elif [ "$STATUS" -ge 200 ] && [ "$STATUS" -lt 300 ]; then
                      echo "Endpoint métier disponible : $endpoint (HTTP $STATUS)"
                    else
                      echo "AVERTISSEMENT : endpoint métier $endpoint retourne HTTP $STATUS"
                    fi
                  done
                '''
            }
        }
    }

    post {
        always {
            archiveArtifacts allowEmptyArchive: true,
                             artifacts: 'trivy-*.txt, .trivyignore, gitleaks-report.json, target/site/jacoco/**'
            sh 'docker image rm -f "$IMAGE" "$DOCKERHUB_REPO:$IMAGE_TAG" >/dev/null 2>&1 || true'
            // Nettoyage des environnements éphémères orphelins : s'exécute TOUJOURS (succès, échec, abandon)
            script { cleanupEphemeralEnvs() }
        }
        success {
            script {
                if (env.DO_DEPLOY == 'true') {
                    echo "${env.FEATURE_SLUG} déployée : http://${env.APP_HOST}/events/  (Grafana : feature = ${env.K8S_NAMESPACE})"
                }
                notifyTeam('SUCCESS', 'good')
            }
        }
        failure {
            script { notifyTeam('FAILURE', 'danger') }
        }
    }
}

// =============================================================================
//  Fonctions utilitaires — la répartition des features est centralisée ICI
// =============================================================================

def ownerOf(String branch) {
    def owners = [
        'feature/event-statistics': 'Roudayna Kouka',
        'feature/initial-setup'   : 'Roudayna Kouka',
        'feature/ci-cd-pipeline'  : 'Roudayna Kouka',
        'feature/participant'     : 'Farah Baraket',
        'feature/logistics'       : 'Ahlem Mastouri',
        'feature/event'           : 'Nour Mustapha',
        'feature/feedback'        : 'Emna Ouarteni',
    ]
    return owners[branch] ?: 'Equipe IGL5-G2'
}

def branchType(String branch) {
    if (branch == 'main')               return 'main'
    if (branch == 'develop')            return 'develop'
    if (branch.startsWith('release/'))  return 'release'
    if (branch.startsWith('hotfix/'))   return 'hotfix'
    return 'feature'
}

def featureSlug(String branch) {
    if (branch == 'main') return 'prod'
    if (branch == 'develop') return 'staging'
    return slugify(branch.replaceFirst(/^(feature|release|hotfix)\//, ''))
}

def namespaceFor(String type, String slug) {
    if (type == 'main') return 'events-prod'
    if (type in ['develop', 'release', 'hotfix']) return 'events-staging'
    return "events-${slug}"
}

def profileFor(String type) {
    if (type == 'main') return 'prod'
    if (type in ['develop', 'release', 'hotfix']) return 'staging'
    return 'review'
}

def slugify(String s) {
    def out = s.toLowerCase()
               .replaceAll(/[àâä]/, 'a').replaceAll(/[éèêë]/, 'e').replaceAll(/[îï]/, 'i')
               .replaceAll(/[ôö]/, 'o').replaceAll(/[ùûü]/, 'u').replaceAll(/ç/, 'c')
               .replaceAll(/[^a-z0-9]+/, '-').replaceAll(/^-+|-+$/, '')
    return out.length() > 40 ? out.substring(0, 40).replaceAll(/-+$/, '') : out
}

// Supprime du dépôt plateforme les envs/<feature> dont la branche n'existe plus.
// Argo CD (ApplicationSet avec prune) supprime alors le namespace => plus de coût orphelin.
// Ne s'exécute que sur develop ; ne fait JAMAIS échouer le build.
def cleanupEphemeralEnvs() {
    if (env.BRANCH_TYPE != 'develop') { return }
    try {
        withCredentials([usernamePassword(credentialsId: 'github-credentials',
                                          usernameVariable: 'GIT_USER', passwordVariable: 'GIT_TOKEN')]) {
            sh '''
              set -e
              AUTH_HEADER="AUTHORIZATION: basic $(printf '%s' "$GIT_USER:$GIT_TOKEN" | base64 | tr -d '\n')"
              APP_URL=$(git config --get remote.origin.url)

              # Si ls-remote échoue, set -e arrête tout : on ne supprime jamais rien « à l'aveugle »
              LIST=$(git -c http.extraheader="$AUTH_HEADER" ls-remote --heads "$APP_URL" 'refs/heads/feature/*')
              ALIVE=$(printf '%s\n' "$LIST" | sed -n 's#.*refs/heads/feature/##p' | tr 'A-Z' 'a-z' \
                      | sed 's/[^a-z0-9]\\+/-/g; s/^-//; s/-$//' | cut -c1-40 | sed 's/-$//')

              rm -rf gitops-clean
              trap 'cd "$WORKSPACE"; rm -rf gitops-clean' EXIT
              git -c http.extraheader="$AUTH_HEADER" clone --branch "$GITOPS_BRANCH" --depth 20 \
                  "https://github.com/$PLATFORM_REPO.git" gitops-clean
              cd gitops-clean

              CHANGED=false
              for d in envs/*; do
                [ -d "$d" ] || continue
                n=$(basename "$d")
                case "$n" in staging|prod) continue;; esac
                if ! printf '%s\n' "$ALIVE" | grep -qx "$n"; then
                  echo "Suppression de l'environnement orphelin : $n"
                  git rm -rq "$d"
                  CHANGED=true
                fi
              done

              if [ "$CHANGED" = true ]; then
                git config user.name  "Jenkins FST"
                git config user.email "jenkins@fst-events.local"
                git commit -m "cleanup: environnements éphémères orphelins [build #$BUILD_NUMBER]"
                PUSHED=false
                for i in 1 2 3; do
                  if git -c http.extraheader="$AUTH_HEADER" push origin "HEAD:$GITOPS_BRANCH"; then
                    PUSHED=true; break
                  fi
                  git -c http.extraheader="$AUTH_HEADER" pull --rebase origin "$GITOPS_BRANCH"
                done
                [ "$PUSHED" = true ] || { echo "Push du nettoyage impossible."; exit 1; }
              else
                echo "Aucun environnement orphelin."
              fi
            '''
        }
    } catch (Exception e) {
        echo "Nettoyage des environnements éphémères ignoré : ${e.message}"
    }
}

def notifyTeam(String status, String color) {
    def msg = "${status} · ${env.FEATURE_SLUG} (#${env.BUILD_NUMBER}) · ${env.OWNER} · ${env.BUILD_URL}"
    try {
        emailext(
            to: env.MAIL_TO,
            subject: "[Jenkins] ${status} · ${env.FEATURE_SLUG} #${env.BUILD_NUMBER}",
            body: "Build ${status}\nBranche : ${env.FEATURE_SLUG}\nResponsable : ${env.OWNER}\n${env.BUILD_URL}"
        )
    } catch (Exception ignored) {
        echo "Notification : ${msg}"
    }
}