// =============================================================================
//  Events Project - FST - IGL5 G2 - Pipeline UNIQUE : CI/CD/DevSecOps (GitOps) + Infra AWS
//
//  UN SEUL Jenkinsfile (job Multibranch Pipeline). Le parametre ACTION choisit le mode :
//
//    ACTION = app            (defaut, push / PR / build auto) : CI/CD de l'application
//    ACTION = infra-plan     : Terraform init + validate + plan (ne change rien)   [feature/logistics]
//    ACTION = infra-apply    : plan + approbation + apply + token Argo CD + ApplicationSet
//    ACTION = infra-destroy  : approbation + nettoyage du cluster + terraform destroy
//
//  Les modes infra-* sont BLOQUES hors de la branche feature/logistics (garde-fou).
//  Les builds declenches automatiquement utilisent toujours ACTION=app (sans danger).
//
//  --- Mode app ---
//  Jenkins = integration continue + securite + publication + PROMOTION GitOps
//  Argo CD = deploiement (modele pull). Jenkins n'a AUCUN acces au cluster pour deployer.
//    feature/<nom>  -> environnement ephemere  events-<nom>
//    develop        -> events-staging
//    release/x.y.z  -> events-staging (gate securite strict)
//    main           -> events-prod    (gate strict + APPROBATION manuelle)
//    PR-*           -> integration continue seulement
//  Variables globales : NEXUS_URL, ECR_REGISTRY, AWS_REGION, APPS_DOMAIN
//  Optionnelles       : PULL_SECRET, SLACK_ENABLED, KIND_NODE, SMOKE_BASE_URL
//  Credentials : nexus-credentials, github-credentials, argocd-token, sonar-token (serveur sonarqube),
//                dockerhub-credentials, aws_access_key_id, aws_secret_access_key, aws_session_token
//
//  --- Mode infra (Terraform "mode PC", etat local) ---
//  create_devops_ec2 = false | argocd_public = true | appset_only_env = logistics | eks_raw = true
//  Credentials en plus : grafana-admin-password, gmail-credentials
// =============================================================================

pipeline {
    agent any

    options {
        timestamps()
        ansiColor('xterm')
        buildDiscarder(logRotator(numToKeepStr: '15', artifactNumToKeepStr: '5'))
        disableConcurrentBuilds()
        timeout(time: 150, unit: 'MINUTES')   // plafond global ; chaque bloc a son propre timeout
    }

    parameters {
        choice(name: 'ACTION', choices: ['app', 'infra-plan', 'infra-apply', 'infra-destroy'],
               description: 'app = CI/CD application | infra-plan = ne change rien | infra-apply = cree VPC + EKS + ECR + Argo CD | infra-destroy = tout supprimer (feature/logistics uniquement)')
        string(name: 'CLUSTER_VERSION', defaultValue: '1.35',
               description: 'Version Kubernetes en SUPPORT STANDARD (le support etendu coute 6 fois plus). Liste : aws eks describe-cluster-versions')
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

        PLATFORM_REPO   = 'AhlemMastouri/Events-Platform'   // owner/repo uniquement
        GITOPS_BRANCH   = 'main'                            // branche suivie par Argo CD
        // Doit correspondre au valueFiles de l'application Argo CD : 'envs' ou 'gitops/envs'
        GITOPS_ENVS_DIR = 'gitops/envs'
        ARGOCD_SERVER   = 'host.docker.internal:8085'       // hote:port, sans http://
    }

    stages {

        // =====================================================================
        //  BLOC 1 : CI/CD APPLICATION  (ACTION = app)
        // =====================================================================
        stage('CI/CD application') {
            when { expression { params.ACTION == 'app' } }
            options { timeout(time: 45, unit: 'MINUTES') }
            stages {

                // -------------------------------------------------------- 1
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
                            if (env.DEPLOY == 'true' && !env.ECR_REGISTRY) {
                                error "Variable globale ECR_REGISTRY non définie (Manage Jenkins > System > Global properties)"
                            }
                            env.IMAGE_TAG     = "${env.FEATURE_SLUG}-${env.BUILD_NUMBER}-${env.GIT_SHORT}"
                            env.IMAGE         = "${env.ECR_REGISTRY ?: 'registry.local'}/${env.APP_NAME}:${env.IMAGE_TAG}"
                            env.SONAR_KEY     = "fst-events-${env.FEATURE_SLUG}"

                            env.APP_HOST      = "${env.ENV_NAME}.${env.APPS_DOMAIN ?: 'apps.local'}"
                            env.BASE_URL      = "${env.SMOKE_BASE_URL ?: 'http://host.docker.internal:8083'}/events"

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

                // -------------------------------------------------------- 2
                stage('Build Maven') {
                    steps {
                        sh "${MVN} versions:set -DnewVersion=${APP_VERSION} -DgenerateBackupPoms=false"
                        sh "${MVN} clean compile"
                    }
                }

                // -------------------------------------------------------- 3
                stage('Tests & couverture') {
                    steps {
                        // Tests Mockito + integration (H2) + rapport JaCoCo + JAR executable
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

                // -------------------------------------------------------- 4
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

                // -------------------------------------------------------- 5
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

                // -------------------------------------------------------- 6
                stage('Quality Gate') {
                    steps {
                        timeout(time: 10, unit: 'MINUTES') {
                            waitForQualityGate abortPipeline: true
                        }
                    }
                }

                // -------------------------------------------------------- 7
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

                // -------------------------------------------------------- 8
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

                // -------------------------------------------------------- 9
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

                // -------------------------------------------------------- 10
                stage('Push image - Amazon ECR') {
                    when { expression { env.DEPLOY == 'true' } }
                    steps {
                        // Identifiants temporaires du Learner Lab (expirent ~4 h)
                        withCredentials([
                            string(credentialsId: 'aws_access_key_id',     variable: 'AWS_ACCESS_KEY_ID'),
                            string(credentialsId: 'aws_secret_access_key', variable: 'AWS_SECRET_ACCESS_KEY'),
                            string(credentialsId: 'aws_session_token',     variable: 'AWS_SESSION_TOKEN')
                        ]) {
                            sh '''
                              set -e

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

                // -------------------------------------------------------- 10c
                stage('Push image - Docker Hub') {
                    when { expression { env.DEPLOY == 'true' } }
                    steps {
                        withCredentials([usernamePassword(credentialsId: 'dockerhub-credentials',
                                                          usernameVariable: 'DH_USER', passwordVariable: 'DH_PSW')]) {
                            sh '''
                              set -e
                              echo "$DH_PSW" | docker login -u "$DH_USER" --password-stdin
                              docker tag "$IMAGE" "$DH_USER/$APP_NAME:$IMAGE_TAG"
                              docker push "$DH_USER/$APP_NAME:$IMAGE_TAG"
                              docker logout
                            '''
                        }
                    }
                }

                // -------------------------------------------------------- 11
                stage('Approbation production') {
                    when { expression { env.BRANCH_TYPE == 'main' } }
                    steps {
                        timeout(time: 24, unit: 'HOURS') {
                            input message: "Promouvoir ${env.IMAGE_TAG} en PRODUCTION ?", ok: 'Promouvoir'
                        }
                    }
                }

                // -------------------------------------------------------- 10b
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

                // -------------------------------------------------------- 12
                stage('Promotion GitOps') {
                    when { expression { env.DEPLOY == 'true' } }
                    steps {
                        withCredentials([usernamePassword(credentialsId: 'github-credentials',
                                                          usernameVariable: 'GIT_USER', passwordVariable: 'GIT_TOKEN')]) {
                            // Jenkins ne deploie pas : il decrit l'etat voulu dans le depot plateforme.
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
                              # Cluster local (kind) : secret de pull ECR. Sur EKS la variable reste vide (role IAM).
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

                // -------------------------------------------------------- 13
                stage('Synchronisation Argo CD') {
                    when { expression { env.DEPLOY == 'true' } }
                    steps {
                        withCredentials([string(credentialsId: 'argocd-token', variable: 'ARGOCD_AUTH_TOKEN')]) {
                            // On attend qu'Argo CD ait applique EXACTEMENT notre revision et que l'appli soit saine.
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

                // -------------------------------------------------------- 14
                stage('Tests post-deploiement') {
                    when { expression { env.DEPLOY == 'true' } }
                    parallel {
                        stage('Smoke tests') {
                            steps {
                                sh '''
                                  BASE="$BASE_URL"
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
                                sh '''
                                  mkdir -p zap-out
                                  CID=$(docker create --user root -v /zap/wrk \
                                          --add-host host.docker.internal:host-gateway "$ZAP_IMAGE" \
                                          zap-baseline.py -t "$BASE_URL/" -I -m 2 -J zap_out.json -r zap_report.html)
                                  set +e
                                  docker start -a "$CID"
                                  RC=$?
                                  set -e
                                  docker cp "$CID:/zap/wrk/." zap-out/ || true
                                  docker rm -v "$CID" >/dev/null
                                  test -s zap-out/zap_out.json || { echo "ZAP n'a produit aucun rapport."; exit 1; }
                                  if [ "$SECURITY_GATE" = "strict" ]; then exit "$RC"; fi
                                '''
                            }
                        }
                    }
                }
            }
        }

        // =====================================================================
        //  BLOC 2 : INFRASTRUCTURE AWS  (ACTION = infra-*, branche feature/logistics)
        // =====================================================================
        stage('Infrastructure AWS') {
            when {
                allOf {
                    expression { params.ACTION.startsWith('infra-') }
                    branch 'feature/logistics'     // garde-fou : jamais d'infra depuis une autre branche
                }
            }
            options { timeout(time: 120, unit: 'MINUTES') }
            environment {
                // Redefinies ici pour ne pas ecraser la variable globale AWS_REGION du bloc app
                AWS_REGION         = 'us-east-1'
                AWS_DEFAULT_REGION = 'us-east-1'
                CLUSTER            = 'fst-events'                 // = variable « project » de platform/terraform
                TF_DIR             = 'platform/terraform'
                // Etat Terraform dans le volume Jenkins (survit au redemarrage, hors Git)
                TF_STATE           = '/var/jenkins_home/tfstate/fst-events.tfstate'
                TF_IN_AUTOMATION   = 'true'
                APPSET_ENV         = 'logistics'                  // seul environnement deploye
                ARGOCD_DIR         = '/var/jenkins_home/argocd'   // adresse + token
                ARGOCD_OPTS        = '--grpc-web --plaintext'     // Argo CD de l'equipe en HTTP (server.insecure)
                KUBECONFIG         = "${WORKSPACE}/.kubeconfig"
            }
            stages {

                stage('Terraform setup') {
                    steps {
                        writeFile file: "${env.TF_DIR}/backend_override.tf", text: """terraform {
  backend "local" {
    path = "${env.TF_STATE}"
  }
}
"""
                        sh '''
                          mkdir -p "$(dirname $TF_STATE)"
                          terraform version
                          trivy config --severity HIGH,CRITICAL --exit-code 0 --skip-dirs '**/.terraform' --format table -o trivy-iac.txt $TF_DIR
                          cd $TF_DIR
                          terraform init -input=false -reconfigure
                          terraform validate
                        '''
                    }
                }

                stage('AWS identity') {
                    steps {
                        script {
                            withAws {
                                try { sh 'aws sts get-caller-identity' }
                                catch (e) { error('AWS refuse les clés : recopie les 3 valeurs (Learner Lab > AWS Details > AWS CLI) dans les credentials Jenkins') }
                                env.LAB_ROLE_ARN = sh(script: 'aws iam get-role --role-name LabRole --query Role.Arn --output text', returnStdout: true).trim()
                                env.MY_IP        = sh(script: 'curl -fsS https://checkip.amazonaws.com', returnStdout: true).trim()
                            }
                            echo "LabRole : ${env.LAB_ROLE_ARN} · IP publique : ${env.MY_IP}"
                            writeFile file: "${env.TF_DIR}/lab.auto.tfvars", text: """region             = "${env.AWS_REGION}"
lab_role_arn       = "${env.LAB_ROLE_ARN}"
cluster_version    = "${params.CLUSTER_VERSION}"
node_instance_type = "t3.large"
admin_cidr         = "${env.MY_IP}/32"
create_devops_ec2  = false
eks_raw            = true
argocd_public      = true
appset_only_env    = "${env.APPSET_ENV}"
"""
                        }
                    }
                }

                stage('Autoriser ton IP sur l\'API EKS') {
                    steps {
                        script {
                            withAws {
                                sh 'ALLOW_MISSING_EKS=1 bash platform/scripts/ensure-eks-access.sh'
                            }
                        }
                    }
                }

                stage('Terraform plan') {
                    when { expression { params.ACTION in ['infra-plan', 'infra-apply'] } }
                    steps {
                        script {
                            withTf {
                                sh '''
                                  cd $TF_DIR
                                  terraform plan -input=false -out=tfplan
                                  terraform show -no-color tfplan > "$WORKSPACE/tfplan.txt"
                                '''
                            }
                        }
                    }
                }

                stage('Approbation : créer l\'infrastructure') {
                    when { expression { params.ACTION == 'infra-apply' } }
                    steps {
                        timeout(time: 30, unit: 'MINUTES') {
                            input message: 'Créer VPC + EKS + ECR + Argo CD maintenant ? (lis tfplan.txt dans les artefacts ; ça consomme du crédit tant que ça tourne)', ok: 'Créer'
                        }
                    }
                }

                stage('Déploiement AWS (terraform apply)') {
                    when { expression { params.ACTION == 'infra-apply' } }
                    steps {
                        script {
                            withTf {
                                sh '''
                                  cd $TF_DIR
                                  terraform apply -input=false tfplan
                                  aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER
                                  kubectl wait --for=condition=Ready nodes --all --timeout=600s
                                  kubectl get nodes
                                '''
                            }
                        }
                    }
                }

                stage('Argo CD : adresse + token') {
                    when { expression { params.ACTION == 'infra-apply' } }
                    steps {
                        script {
                            withAws {
                                sh '''
                                  set +x
                                  aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER >/dev/null
                                  H=""
                                  for i in $(seq 1 60); do
                                    H=$(kubectl -n argocd get svc argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
                                    [ -n "$H" ] && break
                                    echo "Load balancer Argo CD pas encore créé ($i/60)..."; sleep 10
                                  done
                                  [ -n "$H" ] || { echo "Le NLB d'Argo CD n'a pas d'adresse."; exit 1; }
                                  PW=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)

                                  for i in $(seq 1 40); do
                                    argocd login "$H:80" --username admin --password "$PW" >/dev/null 2>&1 && break
                                    echo "Argo CD pas encore joignable ($i/40)..."; sleep 15
                                  done
                                  TOKEN=$(argocd account generate-token --account jenkins --server "$H:80")
                                  [ -n "$TOKEN" ] || { echo "Génération du token échouée."; exit 1; }

                                  umask 077
                                  mkdir -p "$ARGOCD_DIR"
                                  printf '%s' "$H:80"  > "$ARGOCD_DIR/server"
                                  printf '%s' "$TOKEN" > "$ARGOCD_DIR/token"
                                  echo "Argo CD joignable sur http://$H ; token écrit dans $ARGOCD_DIR"
                                '''
                            }
                        }
                    }
                }

                stage('ApplicationSet : environnement logistics') {
                    when { expression { params.ACTION == 'infra-apply' } }
                    steps {
                        script {
                            withAws {
                                sh '''
                                  aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER >/dev/null
                                  for i in $(seq 1 60); do
                                    kubectl -n argocd get appproject events >/dev/null 2>&1 && break
                                    echo "En attente du projet Argo CD « events » ($i/60)..."; sleep 10
                                  done
                                  kubectl -n argocd get appproject events
                                  sed "s#envs/[*]/config.json#envs/$APPSET_ENV/config.json#" platform/gitops/platform/apps/40-events-environments.yaml | kubectl apply -f -
                                  kubectl -n argocd get applicationsets,applications

                                  for i in $(seq 1 90); do
                                    H=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
                                    [ -n "$H" ] && { echo "Load balancer ingress-nginx : $H"; exit 0; }
                                    echo "En attente d'ingress-nginx ($i/90)..."; sleep 10
                                  done
                                  echo "ingress-nginx n'a pas de load balancer : regarde l'application ingress-nginx dans Argo CD."; exit 1
                                '''
                            }
                            echo """Infrastructure prête.
- L'application events-logistics apparaît dans Argo CD après le premier run en ACTION=app (~1 à 3 min).
- Grafana : mot de passe du credential grafana-admin-password (utilisateur admin)
  kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80  -> http://localhost:3000
- Argo CD : http://<adresse dans ${env.ARGOCD_DIR}/server> (utilisateur admin)"""
                        }
                    }
                }

                stage('Approbation : tout détruire') {
                    when { expression { params.ACTION == 'infra-destroy' } }
                    steps {
                        timeout(time: 30, unit: 'MINUTES') {
                            input message: 'DÉTRUIRE le cluster, les nœuds, le VPC et le dépôt ECR ?', ok: 'Détruire'
                        }
                    }
                }

                stage('Destruction (terraform destroy)') {
                    when { expression { params.ACTION == 'infra-destroy' } }
                    steps {
                        script {
                            withTf {
                                sh '''
                                  if aws eks describe-cluster --name $CLUSTER --region $AWS_REGION >/dev/null 2>&1; then
                                    aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER
                                    kubectl -n argocd delete applicationsets,applications --all --timeout=180s || true
                                    kubectl get ns -o name | grep '^namespace/events-' | xargs -r kubectl delete --timeout=300s || true
                                    kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{" "}{.metadata.name}{"\\n"}{end}' | \
                                      while read ns name; do kubectl -n $ns delete svc $name --timeout=300s || true; done
                                    sleep 90
                                  else
                                    echo "Aucun cluster : terraform destroy nettoiera seulement ce qui reste dans l'état"
                                  fi
                                  cd $TF_DIR
                                  terraform destroy -input=false -auto-approve
                                  rm -rf $ARGOCD_DIR
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
                             artifacts: 'trivy-*.txt, .trivyignore, gitleaks-report.json, target/site/jacoco/**, tfplan.txt, trivy-iac.txt'
            script {
                if (params.ACTION == 'app') {
                    sh 'docker image rm -f "$IMAGE" >/dev/null 2>&1 || true'
                } else {
                    sh 'rm -f .kubeconfig platform/terraform/backend_override.tf platform/terraform/lab.auto.tfvars platform/terraform/tfplan || true'
                }
            }
        }
        success {
            script {
                if (params.ACTION == 'app') {
                    if (env.DEPLOY == 'true') {
                        echo "${env.FEATURE_SLUG} deployee : http://${env.APP_HOST}/events/  (Grafana : feature = ${env.K8S_NAMESPACE})"
                    }
                    notifyTeam('SUCCESS', 'good')
                } else {
                    notifyInfra('good', "INFRA ${params.ACTION} OK  #${env.BUILD_NUMBER}")
                }
            }
        }
        failure {
            script {
                if (params.ACTION == 'app') {
                    notifyTeam('FAILURE', 'danger')
                } else {
                    notifyInfra('danger', "INFRA ${params.ACTION} ÉCHEC  #${env.BUILD_NUMBER}")
                }
            }
        }
    }
}

// =============================================================================
//  Fonctions utilitaires - bloc APP (la repartition des features est centralisee ICI)
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

    // E-mail (toujours actif)
    try {
        emailext to: 'ahlemmastouri234@gmail.com',
                 subject: "[Jenkins] ${status} - ${env.FEATURE_SLUG} #${env.BUILD_NUMBER}",
                 body: msg,
                 attachLog: (status == 'FAILURE')
    } catch (Exception e) {
        echo "Mail indisponible : ${e.message}"
    }

    // Slack uniquement si active (SLACK_ENABLED=true)
    if (env.SLACK_ENABLED == 'true') {
        try {
            slackSend(channel: '#igl5-g2-ci', color: color, message: msg)
        } catch (Exception ignored) {
            echo "Slack indisponible : ${ignored.message}"
        }
    }
}

// =============================================================================
//  Fonctions utilitaires - bloc INFRA
// =============================================================================

def withAws(Closure body) {
    withCredentials([
        string(credentialsId: 'aws_access_key_id',     variable: 'AWS_ACCESS_KEY_ID'),
        string(credentialsId: 'aws_secret_access_key', variable: 'AWS_SECRET_ACCESS_KEY'),
        string(credentialsId: 'aws_session_token',     variable: 'AWS_SESSION_TOKEN')
    ]) { body() }
}

// Cles AWS + variables sensibles de Terraform (jamais ecrites dans un fichier)
def withTf(Closure body) {
    withAws {
        withCredentials([
            string(credentialsId: 'grafana-admin-password', variable: 'TF_VAR_grafana_admin_password'),
            usernamePassword(credentialsId: 'github-credentials', usernameVariable: 'GH_USER', passwordVariable: 'TF_VAR_github_token')
        ]) { body() }
    }
}

// Renomme (ancien nom : notify) pour eviter toute confusion avec notifyTeam
def notifyInfra(String color, String text) {
    try {
        withCredentials([usernamePassword(credentialsId: 'gmail-credentials',
                                          usernameVariable: 'GMAIL_USER', passwordVariable: 'GMAIL_PSW')]) {
            emailext from: env.GMAIL_USER,
                     to: env.GMAIL_USER,
                     subject: "[Events INFRA] ${text}",
                     body: "${text}\n${env.BUILD_URL}console",
                     attachLog: (color == 'danger')
        }
    } catch (e) { echo "E-mail non envoyé : ${e.message}" }
}