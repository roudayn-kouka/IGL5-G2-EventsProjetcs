// =============================================================================
//  Events Project - FST - IGL5 G2 - Pipeline CI/CD/DevSecOps (GitOps)
//
//  UN SEUL Jenkinsfile pour TOUTES les branches (job Jenkins Multibranch Pipeline).
//  Repartition des roles :
//    Jenkins  = integration continue + securite + publication + PROMOTION GitOps
//    Argo CD  = deploiement (modele pull) : il lit le depot plateforme et applique sur le cluster
//  => Jenkins n'a AUCUN acces au cluster Kubernetes.
//
//  Contexte deduit du nom de branche (GitFlow) :
//    feature/<nom>  -> environnement ephemere  events-<nom>
//    develop        -> events-staging
//    release/x.y.z  -> events-staging (gate securite strict)
//    main           -> events-prod    (gate strict + APPROBATION manuelle)
//    PR-*           -> integration continue seulement
//
//  Variables globales (Jenkins Configuration as Code / Manage Jenkins) :
//    NEXUS_URL, ECR_REGISTRY, AWS_REGION, APPS_DOMAIN
//  Variables globales OPTIONNELLES :
//    PULL_SECRET   : nom d'un imagePullSecret (cluster kind local, ex: ecr-secret). Vide sur EKS.
//    SLACK_ENABLED : 'true' pour activer les notifications Slack
//  Credentials : nexus-credentials, github-credentials, argocd-token, sonar-token (serveur sonarqube)
//                aws_access_key_id, aws_secret_access_key, aws_session_token (Secret text, Learner Lab)
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
        APP_NAME      = 'events-app'
        TRIVY_IMAGE   = 'aquasec/trivy:0.56.2'
        GITLEAKS_IMG  = 'zricethezav/gitleaks:v8.21.2'
        ZAP_IMAGE     = 'ghcr.io/zaproxy/zaproxy:stable'
        SONAR_PLUGIN  = 'org.sonarsource.scanner.maven:sonar-maven-plugin:3.11.0.3922'
        MVN           = 'mvn -B -ntp'

        // Miroir ECR public : plus fiable que ghcr.io pour la base Trivy
        TRIVY_DB_REPOSITORY      = 'public.ecr.aws/aquasecurity/trivy-db:2'
        TRIVY_JAVA_DB_REPOSITORY = 'public.ecr.aws/aquasecurity/trivy-java-db:1'

        PLATFORM_REPO = 'AhlemMastouri/Events-Platform'   // owner/repo uniquement
        GITOPS_BRANCH = 'main'                            // branche suivie par Argo CD
        // Dossier des environnements dans le depot plateforme. DOIT correspondre au valueFiles
        // de l'application Argo CD : 'envs' (racine) ou 'gitops/envs' selon la structure du depot.
        GITOPS_ENVS_DIR = 'gitops/envs'
        ARGOCD_SERVER = 'host.docker.internal:8085'       // hote:port, sans http://
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
                                        env.APP_VERSION   = (env.BRANCH_TYPE == 'main') ? "1.0.${env.BUILD_NUMBER}" : "1.0.0-${env.FEATURE_SLUG}-SNAPSHOT"
                    if (env.DEPLOY == 'true' && !env.ECR_REGISTRY) {
                        error "Variable globale ECR_REGISTRY non définie (Manage Jenkins > System > Global properties)"
                    }
                    env.IMAGE_TAG     = "${env.FEATURE_SLUG}-${env.BUILD_NUMBER}-${env.GIT_SHORT}"
                    env.IMAGE         = "${env.ECR_REGISTRY ?: 'registry.local'}/${env.APP_NAME}:${env.IMAGE_TAG}"
                    env.SONAR_KEY     = "fst-events-${env.FEATURE_SLUG}"
                    
                    env.APP_HOST      = "${env.ENV_NAME}.${env.APPS_DOMAIN ?: 'apps.local'}"

                    currentBuild.displayName = "#${env.BUILD_NUMBER} - ${env.FEATURE_SLUG}"
                    currentBuild.description = "${env.OWNER} - ${env.GIT_SHORT} - ${env.K8S_NAMESPACE}"

                    echo """
                    ---------------------- Contexte ----------------------
                     Branche        : ${branch}  (${env.BRANCH_TYPE})
                     Responsable    : ${env.OWNER}
                     Version Maven  : ${env.APP_VERSION}
                     Image          : ${env.IMAGE}
                     Projet Sonar   : ${env.SONAR_KEY}
                     Environnement  : ${env.K8S_NAMESPACE}  (profil ${env.HELM_PROFILE})
                     URL            : http://${env.APP_HOST}/events/
                     Gate securite  : ${env.SECURITY_GATE}
                    ------------------------------------------------------"""
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
                // Tests avec Mockito + tests d'integration (H2) + rapport JaCoCo + JAR executable
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
        stage('Securite du code') {
            parallel {
                stage('Secrets - Gitleaks') {
                    steps {
                        // Bloquant partout : un secret commite n'est jamais acceptable
                        sh '''
                          docker run --rm -v "$WORKSPACE:/repo" $GITLEAKS_IMG detect \
                            --source /repo --redact --no-banner \
                            --report-format json --report-path /repo/gitleaks-report.json
                        '''
                    }
                }
                stage('Dependances & IaC - Trivy FS') {
                    steps {
                        retry(3) {
                            sh '''
                              docker run --rm -e TRIVY_DB_REPOSITORY -e TRIVY_JAVA_DB_REPOSITORY \
                                -v "$WORKSPACE:/src" -v trivy-cache:/root/.cache $TRIVY_IMAGE fs \
                                --scanners vuln,misconfig --severity HIGH,CRITICAL --exit-code 0 \
                                --format table --output /src/trivy-fs.txt /src
                              cat trivy-fs.txt
                            '''
                        }
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
                        -Dsonar.projectName='Events - ${FEATURE_SLUG}' \
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
        stage('Publication JAR - Nexus') {
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
        stage('Scan image - Trivy') {
            when { expression { env.DEPLOY == 'true' } }
            steps {
                script {
                    def exitCode = (env.SECURITY_GATE == 'strict') ? '1' : '0'
                    sh """
                      docker run --rm -e TRIVY_DB_REPOSITORY -e TRIVY_JAVA_DB_REPOSITORY \
                        -v /var/run/docker.sock:/var/run/docker.sock \
                        -v "\$WORKSPACE:/reports" -v trivy-cache:/root/.cache ${TRIVY_IMAGE} image \
                        --severity CRITICAL --ignore-unfixed --exit-code ${exitCode} \
                        --ignorefile /reports/.trivyignore \
                        --format table --output /reports/trivy-image.txt ${IMAGE}
                    """
                    sh 'cat trivy-image.txt'
                }
            }
        }

        // ------------------------------------------------------------ 10
        stage('Push image - Amazon ECR') {
            when { expression { env.DEPLOY == 'true' } }
            steps {
                // Identifiants temporaires du Learner Lab, stockes en Secret text dans Jenkins :
                //   aws_access_key_id / aws_secret_access_key / aws_session_token
                // Ils expirent (~4 h) : les mettre a jour a chaque nouvelle session du lab.
                withCredentials([
                    string(credentialsId: 'aws_access_key_id',     variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'aws_secret_access_key', variable: 'AWS_SECRET_ACCESS_KEY'),
                    string(credentialsId: 'aws_session_token',     variable: 'AWS_SESSION_TOKEN')
                ]) {
                    sh '''
                      set -e

                      # Identifiants valides ? (message clair en cas d'expiration)
                      aws sts get-caller-identity --region "$AWS_REGION" >/dev/null \
                        || { echo "Identifiants AWS invalides ou expires : mettez a jour les 3 credentials Jenkins."; exit 1; }

                      aws ecr get-login-password --region "$AWS_REGION" \
                        | docker login --username AWS --password-stdin "$ECR_REGISTRY"
                      docker push "$IMAGE"
                      docker logout "$ECR_REGISTRY"

                      # Verification : l'image est bien presente dans ECR avant de promouvoir
                      aws ecr describe-images --region "$AWS_REGION" --repository-name "$APP_NAME" \
                        --image-ids imageTag="$IMAGE_TAG" >/dev/null \
                        || { echo "Image $IMAGE_TAG absente d'ECR apres le push."; exit 1; }
                      echo "Image $IMAGE_TAG presente dans ECR."
                    '''
                }
            }
        }

        // ------------------------------------------------------------ 11
        stage('Approbation production') {
            when { expression { env.BRANCH_TYPE == 'main' } }
            steps {
                timeout(time: 24, unit: 'HOURS') {
                    input message: "Promouvoir ${env.IMAGE_TAG} en PRODUCTION ?", ok: 'Promouvoir'
                }
            }
        }
                // ------------------------------------------------------------ 10b
        stage('Chargement image - kind local') {
            when {
                allOf {
                    expression { env.DEPLOY == 'true' }
                    expression { env.KIND_NODE }
                }
            }
            steps {
                sh '''
                  set -e
                  # Import dans le containerd du noeud kind : evite le pull ECR (BatchGetImage refuse par le Learner Lab)
                  docker save "$IMAGE" | docker exec -i "$KIND_NODE" ctr -n k8s.io images import --digests --all-platforms -
                  docker exec "$KIND_NODE" crictl images | grep "$IMAGE_TAG" \
                    || { echo "Image $IMAGE_TAG absente du noeud $KIND_NODE apres l'import."; exit 1; }
                  echo "Image $IMAGE_TAG chargee dans $KIND_NODE."
                '''
            }
        }
        // ------------------------------------------------------------ 12
        stage('Promotion GitOps') {
            when { expression { env.DEPLOY == 'true' } }
            steps {
                withCredentials([usernamePassword(credentialsId: 'github-credentials',
                                                  usernameVariable: 'GIT_USER', passwordVariable: 'GIT_TOKEN')]) {
                    // Jenkins ne deploie pas : il decrit l'etat voulu dans le depot plateforme.
                    // L'ApplicationSet Argo CD cree automatiquement l'environnement s'il est nouveau.
                    sh '''
                      set -e
                      rm -rf gitops-work
                      AUTH_HEADER="AUTHORIZATION: basic $(printf '%s' "$GIT_USER:$GIT_TOKEN" | base64 | tr -d '\n')"
                      git -c http.extraheader="$AUTH_HEADER" \
                        clone --branch "$GITOPS_BRANCH" --depth 20 "https://github.com/$PLATFORM_REPO.git" gitops-work
                      trap 'cd "$WORKSPACE"; rm -rf gitops-work' EXIT
                      git -C gitops-work config http.extraheader "$AUTH_HEADER"
                      unset AUTH_HEADER
                      ENV_DIR="gitops-work/$GITOPS_ENVS_DIR/$ENV_NAME"
                      mkdir -p "$ENV_DIR"

                      cat > "$ENV_DIR/config.json" <<EOF
{ "namespace": "$K8S_NAMESPACE", "profile": "$HELM_PROFILE", "owner": "$OWNER_SLUG" }
EOF
                      cat > "$ENV_DIR/values.yaml" <<EOF
# Genere par Jenkins - build #$BUILD_NUMBER - commit $GIT_SHORT - ne pas modifier a la main
feature: $FEATURE_SLUG
owner: $OWNER_SLUG
image:
  repository: $ECR_REGISTRY/$APP_NAME
  tag: $IMAGE_TAG
ingress:
  host: $APP_HOST
EOF
                      # Cluster local (kind) : secret de pull ECR, defini par la variable globale PULL_SECRET.
                      # Sur EKS la variable reste vide : les noeuds s'authentifient par leur role IAM.
                      if [ -n "${PULL_SECRET:-}" ]; then
                        printf 'imagePullSecrets:\n  - name: %s\n' "$PULL_SECRET" >> "$ENV_DIR/values.yaml"
                      fi

                      cd gitops-work
                      git config user.name  "Jenkins FST"
                      git config user.email "jenkins@fst-events.local"
                      git add "$GITOPS_ENVS_DIR/$ENV_NAME"
                      git diff --cached --quiet || git commit -m "deploy($ENV_NAME): $IMAGE_TAG [build #$BUILD_NUMBER - $OWNER]"

                      # Plusieurs membres peuvent promouvoir en meme temps : rebase puis nouvel essai
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
                        echo "Echec du push GitOps apres cinq tentatives."
                        exit 1
                      fi
                      git rev-parse HEAD > ../gitops-revision.txt
                    '''
                }
            }
        }

        // ------------------------------------------------------------ 13
        stage('Synchronisation Argo CD') {
            when { expression { env.DEPLOY == 'true' } }
            steps {
                withCredentials([string(credentialsId: 'argocd-token', variable: 'ARGOCD_AUTH_TOKEN')]) {
                    // On attend qu'Argo CD ait applique EXACTEMENT notre revision et que l'appli soit saine.
                    // API REST (curl) au lieu de la CLI : les erreurs sont visibles dans le log.
                    // Application a source unique => .status.sync.revision (et non .revisions).
                    sh '''
                      set +x
                      APP="events-$ENV_NAME"
                      WANTED=$(cat gitops-revision.txt)
                      URL="https://$ARGOCD_SERVER/api/v1/applications/$APP"
                      for i in $(seq 1 60); do
                        CODE=$(curl -sk -o app.json -w '%{http_code}' \
                          -H "Authorization: Bearer $ARGOCD_AUTH_TOKEN" "$URL?refresh=normal" || echo "000")
                        if [ "$CODE" != "200" ]; then
                          echo "[$i] Argo CD a repondu HTTP $CODE : $(head -c 300 app.json 2>/dev/null)"
                          sleep 10
                          continue
                        fi
                        REV_MATCH=$(jq -r --arg w "$WANTED" '([.status.sync.revision] + (.status.sync.revisions // [])) | index($w) != null' app.json)
                        SYNC=$(jq -r '.status.sync.status // empty' app.json)
                        HEALTH=$(jq -r '.status.health.status // empty' app.json)
                        echo "[$i] $APP commit-attendu=$REV_MATCH sync=$SYNC sante=$HEALTH"
                        if [ "$REV_MATCH" = "true" ] && [ "$SYNC" = "Synced" ] && [ "$HEALTH" = "Healthy" ]; then
                          echo "Deploye et sain."; exit 0
                        fi
                                                if [ "$REV_MATCH" = "true" ] && [ "$SYNC" = "Synced" ] && [ "$HEALTH" = "Degraded" ]; then
                        
                          echo "Deploiement degrade. Ressources en erreur :"
                          jq -r '.status.resources[]? | select(.health.status != null and .health.status != "Healthy") | "\\(.kind)/\\(.name): \\(.health.status) - \\(.health.message // "")"' app.json
                          exit 1
                        fi
                        sleep 10
                      done
                      echo "Delai depasse (10 min)."; exit 1
                    '''
                }
            }
        }

        // ------------------------------------------------------------ 14
        stage('Tests post-deploiement') {
            when { expression { env.DEPLOY == 'true' } }
            parallel {
                stage('Smoke tests') {
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
                            STATUS=${STATUS:-000}
                            if [ "$STATUS" = "404" ]; then
                              echo "AVERTISSEMENT : endpoint metier absent sur cette feature : $endpoint"
                            elif [ "$STATUS" -ge 200 ] && [ "$STATUS" -lt 300 ]; then
                              echo "Endpoint metier disponible : $endpoint (HTTP $STATUS)"
                            else
                              echo "AVERTISSEMENT : endpoint metier $endpoint retourne HTTP $STATUS"
                            fi
                          done
                        '''
                    }
                }
                stage('DAST - OWASP ZAP') {
                    steps {
                        script {
                            def tolerate = (env.SECURITY_GATE == 'strict') ? '' : ' || true'
                            sh "docker run --rm ${ZAP_IMAGE} zap-baseline.py -t http://${env.APP_HOST}/events/ -I -m 2${tolerate}"
                        }
                    }
                }
            }
        }
    }

    post {
        always {
            archiveArtifacts allowEmptyArchive: true,
                             artifacts: 'trivy-*.txt, .trivyignore, gitleaks-report.json, target/site/jacoco/**'
            sh 'docker image rm -f "$IMAGE" >/dev/null 2>&1 || true'
        }
        success {
            script {
                if (env.DEPLOY == 'true') {
                    echo "${env.FEATURE_SLUG} deployee : http://${env.APP_HOST}/events/  (Grafana : feature = ${env.K8S_NAMESPACE})"
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
//  Fonctions utilitaires - la repartition des features est centralisee ICI
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

def notifyTeam(String status, String color) {
    def msg = "${status} - ${env.FEATURE_SLUG} (#${env.BUILD_NUMBER}) - ${env.OWNER} - ${env.BUILD_URL}"
    echo "Notification : ${msg}"
    // Slack uniquement si active (SLACK_ENABLED=true) ET configure dans Manage Jenkins > System
    if (env.SLACK_ENABLED == 'true') {
        try {
            slackSend(channel: '#igl5-g2-ci', color: color, message: msg)
        } catch (Exception ignored) {
            echo "Slack indisponible : ${ignored.message}"
        }
    }
}
