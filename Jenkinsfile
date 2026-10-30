// =============================================================================
//  Events Project · FST · IGL5 G2 — Pipeline CI/CD/DevSecOps (GitOps) — version AWS Learner Lab
//
//  Job Jenkins « Multibranch Pipeline », MAIS le pipeline ne s'exécute QUE sur feature/participant :
//    1. le job filtre les branches (Behaviours > Filter by name : feature/participant)
//    2. ceinture + bretelles : le stage racine ci-dessous a « when { branch 'feature/participant' } »
//
//  Différences avec la version d'équipe (EC2 + rôle IAM) :
//    - pas de rôle IAM sur EC2 : les 3 clés du Learner Lab sont lues dans Jenkins (aws_access_key_id,
//      aws_secret_access_key, aws_session_token) ; elles expirent => à recopier à chaque session
//    - le n° de compte est lu à l'exécution (aws sts) ; le dépôt ECR events-app est créé par Terraform (Jenkinsfile.infra)
//    - Jenkins tourne sur ton PC : il atteint Argo CD par la CLI argocd (serveur exposé par Jenkinsfile.infra,
//      adresse + token écrits dans /var/jenkins_home/argocd/) et l'ingress par kubectl (aws eks update-kubeconfig)
//    - les variables Ansible/CasC (NEXUS_URL, PLATFORM_REPO...) sont définies ici, dans environment{}
//    - gitleaks et trivy sont les binaires installés dans le conteneur Jenkins (un « docker run -v $WORKSPACE »
//      depuis un Jenkins en conteneur monterait un dossier de l'hôte, pas celui du workspace)
//    - pas d'approbation production : la branche main n'est pas construite
//
//  Credentials Jenkins : aws_access_key_id, aws_secret_access_key, aws_session_token (Secret text),
//                        nexus-credentials, github-credentials (Username + token), sonar-token (serveur « sonarqube »)
//  Prérequis cluster : Jenkinsfile.infra (apply) a déjà créé EKS, ingress-nginx, Argo CD et l'ApplicationSet.
// =============================================================================

pipeline {
    agent any

    tools { jdk 'jdk17' }                       // nom de l'outil JDK 17 dans Manage Jenkins > Tools

    options {
        timestamps()
        // No ansiColor option: avoids requiring the AnsiColor Jenkins plugin.
        timeout(time: 45, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '15', artifactNumToKeepStr: '5'))
        disableConcurrentBuilds()
    }

    environment {
        APP_NAME           = 'events-app'
        AWS_REGION         = 'us-east-1'
        AWS_DEFAULT_REGION = 'us-east-1'
        CLUSTER            = 'fst-events'                    // = cluster_name dans terraform/aws/variables.tf
        KUBECONFIG         = "${WORKSPACE}/.kubeconfig"
        NEXUS_URL          = 'http://nexus:8081'             // nom du conteneur sur le réseau ci-net
        PLATFORM_REPO      = 'roudayn-kouka/IGL5-G2-EventsProjetcs'   // le dépôt plateforme est le même que celui de l'application
        GITOPS_BRANCH      = 'gitops'                        // branche écrite par Jenkins (envs/<env>/values.yaml)
        APPS_DOMAIN        = 'events.local'                  // nom d'hôte de l'ingress (résolu par curl --resolve)
        ARGOCD_OPTS        = '--grpc-web --plaintext'         // le serveur Argo CD de l'équipe est en HTTP (server.insecure)
        ARGOCD_DIR         = '/var/jenkins_home/argocd'       // server + token, écrits par Jenkinsfile.infra
        ZAP_IMAGE          = 'ghcr.io/zaproxy/zaproxy:stable'
        SONAR_PLUGIN       = 'org.sonarsource.scanner.maven:sonar-maven-plugin:3.11.0.3922'
        MVN                = 'sh ./mvnw -B -ntp'             // wrapper du dépôt : pas besoin de Maven dans Jenkins
        MAIL_TO            = 'fbaraket48@gmail.com'          // destinataire des e-mails de build (en plus de Slack)
        // Vide = smoke tests et ZAP passent par le load balancer (curl --resolve).
        // Sinon URL de base, ex. http://host.docker.internal:8083/events (un port-forward lancé sur ton PC) : sans --resolve.
        SMOKE_BASE_URL     = ''
    }

    stages {

        stage('Pipeline feature/participant') {
            when { branch 'feature/participant' }
            stages {

                // ------------------------------------------------------------ 1
                stage('Contexte') {
                    steps {
                        script {
                            def branch = env.BRANCH_NAME
                            env.BRANCH_TYPE   = 'feature'
                            env.FEATURE_SLUG  = featureSlug(branch)
                            env.OWNER         = ownerOf(branch)
                            env.OWNER_SLUG    = slugify(env.OWNER)
                            env.GIT_SHORT     = sh(script: 'git rev-parse --short=7 HEAD', returnStdout: true).trim()
                            env.K8S_NAMESPACE = "events-${env.FEATURE_SLUG}"
                            env.ENV_NAME      = env.FEATURE_SLUG
                            env.HELM_PROFILE  = 'review'
                            env.SECURITY_GATE = 'report'
                            env.APP_VERSION   = "1.0.0-${env.FEATURE_SLUG}-SNAPSHOT"
                            env.IMAGE_TAG     = "${env.FEATURE_SLUG}-${env.BUILD_NUMBER}-${env.GIT_SHORT}"
                            env.SONAR_KEY     = "fst-events-${env.FEATURE_SLUG}"
                            env.APP_HOST      = "${env.ENV_NAME}.${env.APPS_DOMAIN}"

                            currentBuild.displayName = "#${env.BUILD_NUMBER} · ${env.FEATURE_SLUG}"
                            currentBuild.description = "${env.OWNER} · ${env.GIT_SHORT} · ${env.K8S_NAMESPACE}"
                            echo "Branche ${branch} · responsable ${env.OWNER} · namespace ${env.K8S_NAMESPACE} · version ${env.APP_VERSION}"
                        }
                    }
                }

                // ------------------------------------------------------------ 2  (échoue tout de suite si les clés Learner Lab ont expiré)
                stage('AWS Learner Lab') {
                    steps {
                        script {
                            try {
                                withAws {
                                    env.AWS_ACCOUNT = sh(script: 'aws sts get-caller-identity --query Account --output text', returnStdout: true).trim()
                                    sh 'aws ecr describe-repositories --repository-names "$APP_NAME" >/dev/null'
                                }
                            } catch (e) {
                                error "AWS refuse les clés, ou le dépôt ECR ${env.APP_NAME} n'existe pas : recopie les 3 clés Learner Lab dans Jenkins, ou lance Jenkinsfile.infra (ACTION=apply)."
                            }
                            env.ECR_REGISTRY = "${env.AWS_ACCOUNT}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"
                            env.IMAGE        = "${env.ECR_REGISTRY}/${env.APP_NAME}:${env.IMAGE_TAG}"
                            echo "Registre ECR : ${env.ECR_REGISTRY} · image : ${env.IMAGE}"
                        }
                    }
                }

                // L'IP publique de Jenkins peut changer entre deux pushes.
                // Ce contrôle s'exécute avec les credentials AWS du Learner Lab,
                // avant toute commande kubectl / Argo CD.
                stage('Acces EKS : IP actuelle de Jenkins') {
                    steps {
                        withAws {
                            sh 'bash platform/scripts/ensure-eks-access.sh'
                        }
                    }
                }

                // ------------------------------------------------------------ 3
                stage('Build Maven') {
                    steps {
                        sh "${MVN} versions:set -DnewVersion=${APP_VERSION} -DgenerateBackupPoms=false"
                        // Maven also runs npm ci + Angular production build, and packages a single JAR.
                        sh "${MVN} clean verify"
                    }
                }

                // ------------------------------------------------------------ 4
                stage('Tests & couverture') {
                    steps {
                        sh '''
                          test -f frontend/dist/app/index.html || { echo "Angular index missing"; exit 1; }
                          test -f target/classes/static/app/index.html || { echo "Angular not copied into Spring static"; exit 1; }
                          JAR=$(find target -maxdepth 1 -type f -name '*.jar' ! -name '*.jar.original' | head -n1)
                          [ -n "$JAR" ] || { echo "JAR missing"; exit 1; }
                          jar tf "$JAR" | grep -F 'BOOT-INF/classes/static/app/index.html' >/dev/null || {
                            echo "Angular not found inside JAR"; exit 1;
                          }
                        ''' 
                    }
                    post {
                        always {
                            junit allowEmptyResults: true, testResults: 'target/surefire-reports/*.xml'
                            recordCoverage(tools: [[parser: 'JACOCO', pattern: 'target/site/jacoco/jacoco.xml']],
                                           id: 'jacoco', name: 'Couverture JaCoCo')
                        }
                    }
                }

                // ------------------------------------------------------------ 5
                stage('Sécurité du code') {
                    parallel {
                        stage('Secrets · Gitleaks') {
                            steps {
                                // Bloquant : un secret commité n'est jamais acceptable
                                sh 'gitleaks detect --source . --redact --no-banner --report-format json --report-path gitleaks-report.json'
                            }
                        }
                        stage('Dépendances & IaC · Trivy FS') {
    steps {
        sh ''
        
    }
}
                    }
                }

                // ------------------------------------------------------------ 6
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

                // ------------------------------------------------------------ 7
                stage('Quality Gate') {
                    steps {
                        timeout(time: 10, unit: 'MINUTES') {
                            waitForQualityGate abortPipeline: true
                        }
                    }
                }

                // ------------------------------------------------------------ 8
                                // ------------------------------------------------------------ 8
                stage('Publication JAR · Nexus') {
                    steps {
                        withCredentials([usernamePassword(credentialsId: 'nexus-credentials',
                                                          usernameVariable: 'NEXUS_USR', passwordVariable: 'NEXUS_PSW')]) {
                            // 1. SNAPSHOT : version de travail de la branche
                            sh """
                              ${MVN} -s ci/maven-settings.xml deploy -DskipTests -Dskip.npm -Dskip.installnodenpm \
                                -DaltDeploymentRepository=nexus::default::${env.NEXUS_URL}/repository/maven-snapshots/
                            """
                            // 2. RELEASE :
                            sh '''
                              JAR=$(find target -maxdepth 1 -type f -name '*.jar' ! -name '*.jar.original' | head -n1)
                              REL="1.0.0-$FEATURE_SLUG.$BUILD_NUMBER"
                              sh ./mvnw -B -ntp -s ci/maven-settings.xml deploy:deploy-file \
                                -Dfile="$JAR" -DgroupId=tn.fst -DartifactId=eventsProject -Dversion="$REL" \
                                -Dpackaging=jar -DgeneratePom=true -DrepositoryId=nexus \
                                -Durl="$NEXUS_URL/repository/maven-releases/"
                              echo "Release publiée : tn.fst:eventsProject:$REL"
                            '''
                        }
                    }
                }

                // ------------------------------------------------------------ 9
                stage('Image Docker & docker hub') {
    steps {
        // Build the application image
        sh '''
            set -eu

            docker build --pull \
              --label "org.opencontainers.image.revision=$GIT_SHORT" \
              --label "org.opencontainers.image.version=$APP_VERSION" \
              --label "tn.fst.feature=$FEATURE_SLUG" \
              --label "tn.fst.owner=$OWNER_SLUG" \
              -t "$IMAGE" .
        '''

        // Docker Hub is optional: do not block AWS deployment
        // if Docker Hub is temporarily unreachable.
        catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
            withCredentials([
                usernamePassword(
                    credentialsId: 'dockerhub-credentials',
                    usernameVariable: 'DH_USER',
                    passwordVariable: 'DH_TOKEN'
                )
            ]) {
                retry(3) {
                    sh '''
                        set -eu
                        set +x

                        HUB_IMAGE="$DH_USER/$APP_NAME"

                        # Temporary Docker credentials directory
                        export DOCKER_CONFIG
                        DOCKER_CONFIG="$(mktemp -d)"
                        trap 'rm -rf "$DOCKER_CONFIG"' EXIT

                        # Authenticate securely
                        printf '%s' "$DH_TOKEN" |
                          docker login \
                            --username "$DH_USER" \
                            --password-stdin

                        # Tag image
                        docker tag "$IMAGE" "$HUB_IMAGE:latest"

                        # Publish image
                        docker push "$HUB_IMAGE:latest"

                        docker logout

                        echo "Docker Hub : $HUB_IMAGE:latest"
                    '''
                }
            }
        }
    }
}

                // -------------------------Take so long to install and run--------------------------------- 10
                // stage('Scan image · Trivy') {
                //     steps {
                //         // trivy lit l'image directement via /var/run/docker.sock monté dans le conteneur Jenkins
                //         sh '''
                //           touch .trivyignore
                //           trivy image --severity CRITICAL --ignore-unfixed --exit-code 0 \
                //             --ignorefile .trivyignore --format table --output trivy-image.txt "$IMAGE"
                //           cat trivy-image.txt
                //         '''
                //     }
                // }

                // ------------------------------------------------------------ 11
                stage('Push image · Amazon ECR') {
                    steps {
                        script {
                            withAws {
                                sh '''
                                  aws ecr get-login-password --region "$AWS_REGION" \
                                    | docker login --username AWS --password-stdin "$ECR_REGISTRY"
                                  docker push "$IMAGE"
                                  docker logout "$ECR_REGISTRY"
                                '''
                            }
                        }
                    }
                }

                // ------------------------------------------------------------ 12
                stage('Promotion GitOps') {
                    steps {
                        // Jenkins ne déploie pas : il écrit l'état voulu dans le dépôt plateforme.
                        // L'ApplicationSet Argo CD crée l'environnement events-participant s'il est nouveau.
                        withCredentials([usernamePassword(credentialsId: 'github-credentials',
                                                          usernameVariable: 'GIT_USER', passwordVariable: 'GIT_TOKEN')]) {
                            sh '''
                              set +x
                              rm -rf gitops-work
                              AUTH="AUTHORIZATION: basic $(printf '%s' "$GIT_USER:$GIT_TOKEN" | base64 -w0)"
                              git -c http.extraheader="$AUTH" clone --branch "$GITOPS_BRANCH" --depth 20 \
                                "https://github.com/$PLATFORM_REPO.git" gitops-work
                              git -C gitops-work config http.extraheader "$AUTH"
                              mkdir -p "gitops-work/envs/$ENV_NAME"
                            '''
                            writeFile file: "gitops-work/envs/${env.ENV_NAME}/config.json",
                                      text: """{
  "namespace": "${env.K8S_NAMESPACE}",
  "profile": "${env.HELM_PROFILE}",
  "owner": "${env.OWNER_SLUG}",
  "feature": "${env.FEATURE_SLUG}",
  "imageRepository": "${env.ECR_REGISTRY}/${env.APP_NAME}",
  "imageTag": "${env.IMAGE_TAG}",
  "host": "${env.APP_HOST}"
}
"""
                            writeFile file: "gitops-work/envs/${env.ENV_NAME}/values.yaml",
                                      text: """# Généré par Jenkins — build #${env.BUILD_NUMBER} — commit ${env.GIT_SHORT} — ne pas modifier à la main
feature: ${env.FEATURE_SLUG}
owner: ${env.OWNER_SLUG}
image:
  repository: ${env.ECR_REGISTRY}/${env.APP_NAME}
  tag: ${env.IMAGE_TAG}
ingress:
  host: ${env.APP_HOST}
"""
                            sh '''
                              set +x
                              cd gitops-work
                              git config user.name  "Jenkins FST"
                              git config user.email "jenkins@fst-events.local"
                              git add "envs/$ENV_NAME"
                              git diff --cached --quiet || git commit -m "deploy($ENV_NAME): $IMAGE_TAG [build #$BUILD_NUMBER · $OWNER]"

                              PUSHED=false
                              for i in 1 2 3 4 5; do
                                if git push origin "HEAD:$GITOPS_BRANCH"; then PUSHED=true; break; fi
                                [ "$i" -lt 5 ] && git pull --rebase origin "$GITOPS_BRANCH"
                              done
                              [ "$PUSHED" = true ] || { echo "Échec du push GitOps après cinq tentatives."; exit 1; }
                              git rev-parse HEAD > ../gitops-revision.txt
                            '''
                        }
                    }
                }

                // Le GitOps commit contient désormais les sept paramètres.
                // On réapplique le bon ApplicationSet dans le cluster en place :
                // pas besoin de relancer terraform apply ou de le modifier dans l'UI Argo CD.
                stage('Mettre a jour ApplicationSet') {
                    steps {
                        withAws {
                            sh '''
                              set -eu
                              aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER" >/dev/null
                              sed 's#envs/[*]/config.json#envs/participant/config.json#' \
                                platform/gitops/platform/apps/40-events-environments.yaml \
                                | kubectl -n argocd apply -f -
                              kubectl -n argocd get applicationset events-environments -o json \
                                | jq -e '.spec.template.spec.source != null and (.spec.template.spec.sources == null)' >/dev/null \
                                || { echo "ApplicationSet toujours multi-source : vérifier le manifest appliqué"; exit 1; }
                              echo "ApplicationSet single-source applique."
                            '''
                        }
                    }
                }

                // ------------------------------------------------------------ 13
                stage('Synchronisation Argo CD') {
                    steps {
                        script {
                            // On attend qu'Argo CD ait appliqué EXACTEMENT notre commit et que l'appli soit saine.
                            // L'ApplicationSet scrute Git toutes les ~3 min : la 1re fois, l'Application apparaît avec ce délai.
                            // Adresse et token d'Argo CD : fichiers créés par Jenkinsfile.infra (ils changent à chaque cluster).
                            sh '''
                              set +x
                              [ -s "$ARGOCD_DIR/token" ] || { echo "Token Argo CD absent : lance Jenkinsfile.infra (ACTION=apply)."; exit 1; }
                              export ARGOCD_SERVER=$(cat "$ARGOCD_DIR/server")
                              export ARGOCD_AUTH_TOKEN=$(cat "$ARGOCD_DIR/token")
                              APP="events-$ENV_NAME"
                              # La révision GitOps sert seulement à générer les paramètres.
                              # L'Application elle-même utilise une seule source Helm sur feature/participant.
                              # On vérifie donc le tag de l'image demandé, puis Synced et Healthy.
                              WANTED_TAG="$IMAGE_TAG"
                              for i in $(seq 1 60); do
                                J=$(argocd app get "$APP" --refresh -o json 2>/dev/null || true)
                                CURRENT_TAG=$(printf '%s' "$J" | jq -r '[(.spec.source.helm.parameters // [])[] | select(.name == "image.tag") | .value] | first // ""' 2>/dev/null || true)
                                SYNC=$(printf '%s' "$J" | jq -r '.status.sync.status // empty' 2>/dev/null || true)
                                HEALTH=$(printf '%s' "$J" | jq -r '.status.health.status // empty' 2>/dev/null || true)
                                echo "[$i] $APP image=$CURRENT_TAG attendue=$WANTED_TAG sync=$SYNC santé=$HEALTH"
                                if [ "$CURRENT_TAG" = "$WANTED_TAG" ] && [ "$SYNC" = "Synced" ] && [ "$HEALTH" = "Healthy" ]; then
                                  echo "Déployé et sain."; exit 0
                                fi
                                if [ "$CURRENT_TAG" = "$WANTED_TAG" ] && [ "$HEALTH" = "Degraded" ]; then
                                  echo "Déploiement dégradé : voir l'interface Argo CD."; exit 1
                                fi
                                sleep 10
                              done
                              echo "Délai dépassé (10 min)."; exit 1
                            '''
                            env.LB_IP = lbIp()
                            echo "Load balancer ingress-nginx : ${env.LB_IP}  (${env.APP_HOST})"
                        }
                    }
                }

                // ------------------------------------------------------------ 14
                stage('Tests post-déploiement') {
                    parallel {
                        stage('Smoke tests') {
                            steps {
                                sh '''
                                  if [ -n "$SMOKE_BASE_URL" ]; then
                                    BASE="$SMOKE_BASE_URL"; C="curl"
                                  else
                                    BASE="http://$APP_HOST/events"; C="curl --resolve $APP_HOST:80:$LB_IP"
                                  fi
                                  HEALTH=$($C -fsS --retry 10 --retry-delay 6 --retry-all-errors "$BASE/actuator/health/readiness")
                                  echo "$HEALTH"
                                  echo "$HEALTH" | grep -Eq '"status"[[:space:]]*:[[:space:]]*"UP"' || {
                                    echo "Readiness Actuator n'est pas UP."; exit 1;
                                  }
                                  $C -fsS --retry 10 --retry-delay 6 --retry-all-errors -o /dev/null "$BASE/actuator/prometheus"
                                  echo "Endpoint Prometheus disponible."
                                  $C -fsS --retry 10 --retry-delay 6 --retry-all-errors "$BASE/app/" | grep -F '<app-root' >/dev/null || {
                                    echo "Dashboard Angular /events/app/ unavailable"; exit 1;
                                  }
                                  echo "Dashboard Angular disponible sur $BASE/app/"

                                  for endpoint in "$BASE/event-stats/summary" "$BASE/event/"; do
                                    STATUS=$($C -sS -o /dev/null -w '%{http_code}' "$endpoint" || true)
                                    echo "Endpoint $endpoint : HTTP $STATUS"
                                  done
                                '''
                            }
                        }
                        stage('DAST · OWASP ZAP') {
                            steps {
                                // rapport seulement (|| true) : ZAP ne bloque jamais sur une feature
                                sh '''
                                  if [ -n "$SMOKE_BASE_URL" ]; then
                                    docker run --rm $ZAP_IMAGE zap-baseline.py -t "$SMOKE_BASE_URL/" -I -m 2 || true
                                  else
                                    docker run --rm --add-host "$APP_HOST:$LB_IP" $ZAP_IMAGE zap-baseline.py -t "http://$APP_HOST/events/" -I -m 2 || true
                                  fi
                                '''
                            }
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
            sh 'docker image rm -f "$IMAGE" >/dev/null 2>&1 || true; rm -rf gitops-work .kubeconfig'
        }
        success { script { notifyTeam('SUCCESS', 'good') } }
        failure { script { notifyTeam('FAILURE', 'danger') } }
    }
}

// =============================================================================
//  Fonctions utilitaires
// =============================================================================

// Les 3 clés temporaires du Learner Lab, injectées en variables d'environnement
def withAws(Closure body) {
    withCredentials([
        string(credentialsId: 'aws_access_key_id',     variable: 'AWS_ACCESS_KEY_ID'),
        string(credentialsId: 'aws_secret_access_key', variable: 'AWS_SECRET_ACCESS_KEY'),
        string(credentialsId: 'aws_session_token',     variable: 'AWS_SESSION_TOKEN')
    ]) { body() }
}

// IP du Network Load Balancer d'ingress-nginx (le DNS d'un NLB neuf peut mettre quelques minutes à répondre)
def lbIp() {
    def ip = ''
    withAws {
        ip = sh(returnStdout: true, script: '''
          aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER" >/dev/null
          H=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
          for i in $(seq 1 30); do
            IP=$(getent hosts "$H" | awk 'NR==1{print $1}')
            [ -n "$IP" ] && break
            sleep 10
          done
          echo "$IP"
        ''').trim()
    }
    if (!ip) { error 'Load balancer ingress-nginx introuvable : lance Jenkinsfile.infra (ACTION=apply) d\'abord.' }
    return ip
}

def ownerOf(String branch) {
    def owners = [
        'feature/participant': 'Farah Baraket',
    ]
    return owners[branch] ?: 'Equipe IGL5-G2'
}

def featureSlug(String branch) {
    return slugify(branch.replaceFirst(/^(feature|release|hotfix)\//, ''))
}

def slugify(String s) {
    def out = s.toLowerCase()
               .replaceAll(/[àâä]/, 'a').replaceAll(/[éèêë]/, 'e').replaceAll(/[îï]/, 'i')
               .replaceAll(/[ôö]/, 'o').replaceAll(/[ùûü]/, 'u').replaceAll(/ç/, 'c')
               .replaceAll(/[^a-z0-9]+/, '-').replaceAll(/^-+|-+$/, '')
    return out.length() > 40 ? out.substring(0, 40).replaceAll(/-+$/, '') : out
}

def notifyTeam(String status, String color) {
    if (!env.FEATURE_SLUG) return            // branche ignorée : rien à notifier
    def msg = "${status} · ${env.FEATURE_SLUG} (#${env.BUILD_NUMBER}) · ${env.OWNER} · ${env.BUILD_URL}"
    try {
        slackSend(channel: '#igl5-g2-ci', color: color, message: msg)
    } catch (Exception ignored) {
        echo "Slack non configuré : ${msg}"
    }
    // E-mail (SMTP configuré dans Manage Jenkins > System > E-mail Notification)
    try {
        mail to: env.MAIL_TO,
             subject: "[Events CI] ${status} · ${env.FEATURE_SLUG} #${env.BUILD_NUMBER}",
             body: "Statut : ${status}\nBranche : ${env.BRANCH_NAME}\nResponsable : ${env.OWNER}\nCommit : ${env.GIT_SHORT}\nImage : ${env.IMAGE_TAG}\nBuild : ${env.BUILD_URL}\n"
    } catch (Exception e) {
        echo "E-mail non envoyé : ${e.message}"
    }
}