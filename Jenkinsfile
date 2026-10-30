// =============================================================================
//  Events Project · FST · IGL5 G2 — Pipeline CI/CD/DevSecOps (GitOps)
//
//  UN SEUL Jenkinsfile pour TOUTES les branches (job Jenkins « Multibranch Pipeline »).
//  Répartition des rôles :
//    Jenkins  = intégration continue + sécurité + publication + PROMOTION GitOps
//    Argo CD  = déploiement (modèle « pull ») : il lit le dépôt plateforme et applique sur EKS
//  => Jenkins n'a AUCUN accès au cluster Kubernetes.
//
//  Contexte déduit du nom de branche (GitFlow) :
//    feature/<nom>  -> environnement éphémère  events-<nom>
//    develop        -> events-staging
//    release/x.y.z  -> events-staging (gate sécurité strict)
//    main           -> events-prod    (gate strict + APPROBATION manuelle)
//    PR-*           -> intégration continue seulement
//
//  Variables globales (injectées par Ansible via Jenkins Configuration as Code) :
//    NEXUS_URL, ECR_REGISTRY, AWS_REGION, PLATFORM_REPO, GITOPS_BRANCH, ARGOCD_SERVER, APPS_DOMAIN
//  Credentials : nexus-credentials, github-credentials, argocd-token, sonar-token (serveur « sonarqube »)
// =============================================================================

pipeline {
    agent any

    options {
        timestamps()
        ansiColor('xterm')
        // EKS creation and node readiness can exceed the CI-only timeout. The Terraform
        // path remains opt-in and has its own approval gates.
        timeout(time: 120, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '15', artifactNumToKeepStr: '5'))
        disableConcurrentBuilds()
    }

    environment {
        APP_NAME     = 'events-app'
        TRIVY_IMAGE  = 'aquasec/trivy:0.56.2'
        GITLEAKS_IMG = 'zricethezav/gitleaks:v8.21.2'
        ZAP_IMAGE    = 'ghcr.io/zaproxy/zaproxy:stable'
        SONAR_PLUGIN = 'org.sonarsource.scanner.maven:sonar-maven-plugin:3.11.0.3922'
        MVN          = 'mvn -B -ntp'
        ARGOCD_OPTS  = '--grpc-web --plaintext'
    }

    parameters {
        // Shared infrastructure is never created by an ordinary application build.
        booleanParam(name: 'PROVISION_INFRASTRUCTURE', defaultValue: false,
                     description: 'Develop only: create/update the shared Terraform platform after two reviewed plans and approvals.')
        booleanParam(name: 'RUN_ZAP', defaultValue: true,
                     description: 'Run the existing OWASP ZAP baseline scan after deployment.')
        booleanParam(name: 'LOCAL_DEMO', defaultValue: false,
                     description: 'Feature-only local CI/CD demo: deploy the scanned image with Docker Compose and skip AWS, GitOps and Argo CD actions.')
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
                    env.LOCAL_DEMO    = params.LOCAL_DEMO ? 'true' : 'false'
                    env.DEPLOY        = (env.BRANCH_TYPE == 'pr' || params.LOCAL_DEMO) ? 'false' : 'true'
                    env.SECURITY_GATE = (env.BRANCH_TYPE in ['main', 'release']) ? 'strict' : 'report'
                    env.APP_VERSION   = (env.BRANCH_TYPE == 'main') ? "1.0.${env.BUILD_NUMBER}" : "1.0.0-${env.FEATURE_SLUG}-SNAPSHOT"
                    env.IMAGE_TAG     = "${env.FEATURE_SLUG}-${env.BUILD_NUMBER}-${env.GIT_SHORT}"
                    env.IMAGE         = params.LOCAL_DEMO ? "${env.APP_NAME}:local-${env.IMAGE_TAG}" : "${env.ECR_REGISTRY ?: 'registry.local'}/${env.APP_NAME}:${env.IMAGE_TAG}"
                    env.SONAR_KEY     = "fst-events-${env.FEATURE_SLUG}"
                    env.APP_HOST      = params.LOCAL_DEMO ? 'host.docker.internal:9090' : "${env.ENV_NAME}.${env.APPS_DOMAIN ?: 'apps.local'}"
                    env.DOCKER_WORKSPACE = params.LOCAL_DEMO
                        ? "/var/lib/docker/volumes/events-ci-agent-work/_data${env.WORKSPACE.replaceFirst('^/home/jenkins/agent', '')}"
                        : env.WORKSPACE

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
                // Tests avec Mockito + tests d'intégration (H2) + rapport JaCoCo + JAR exécutable
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
                        // Bloquant partout : un secret commité n'est jamais acceptable
                        sh '''
                          docker run --rm -v "$DOCKER_WORKSPACE:/repo" $GITLEAKS_IMG detect \
                            --source /repo --redact --no-banner \
                            --report-format json --report-path /repo/gitleaks-report.json
                        '''
                    }
                }
                stage('Dépendances & IaC · Trivy FS') {
                    steps {
                        sh '''
                          docker run --rm -v "$DOCKER_WORKSPACE:/src" -v trivy-cache:/root/.cache $TRIVY_IMAGE fs \
                            --scanners vuln,misconfig --severity HIGH,CRITICAL --exit-code 0 \
                            --format table --output /src/trivy-fs.txt /src
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
            when { expression { env.DEPLOY == 'true' || params.LOCAL_DEMO } }
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
        // A new EKS account cannot plan Kubernetes/Helm resources until the cluster
        // exists. The repository-owned academy.ps1 uses this same bootstrap split.
        // These stages are deliberately limited to develop: shared infrastructure is
        // not owned by a feature branch, and main is never provisioned.
        stage('Terraform init, fmt & validate') {
            when {
                beforeAgent true
                expression { terraformProvisioningRequested() }
            }
            steps {
                withCredentials([
                    file(credentialsId: 'aws-academy-credentials', variable: 'AWS_SHARED_CREDENTIALS_FILE'),
                    file(credentialsId: 'terraform-backend-config', variable: 'TF_BACKEND_CONFIG')
                ]) {
                    sh '''#!/usr/bin/env bash
set +x
set -euo pipefail
: "${AWS_REGION:?AWS_REGION must be configured}"
: "${AWS_SHARED_CREDENTIALS_FILE:?AWS Academy credentials are required}"
: "${TF_BACKEND_CONFIG:?Terraform backend configuration is required}"
export AWS_PAGER=''
export AWS_CONFIG_FILE=/dev/null
export AWS_EC2_METADATA_DISABLED=true
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN
unset AWS_PROFILE AWS_DEFAULT_PROFILE AWS_ROLE_ARN AWS_WEB_IDENTITY_TOKEN_FILE
command -v terraform >/dev/null || { echo 'ERROR: Terraform is missing from the Jenkins agent image.' >&2; exit 1; }
if ! aws sts get-caller-identity --region "$AWS_REGION" >/dev/null; then
  echo 'ERROR: AWS Academy authentication failed. Refresh aws-academy-credentials and retry.' >&2
  exit 1
fi
terraform -chdir=platform/terraform init -input=false -lockfile=readonly -backend-config="$TF_BACKEND_CONFIG"
terraform -chdir=platform/terraform fmt -check -recursive
terraform -chdir=platform/terraform validate
'''
                }
            }
        }

        stage('Terraform bootstrap plan') {
            when {
                beforeAgent true
                expression { terraformProvisioningRequested() }
            }
            steps {
                withCredentials([
                    file(credentialsId: 'aws-academy-credentials', variable: 'AWS_SHARED_CREDENTIALS_FILE'),
                    file(credentialsId: 'terraform-backend-config', variable: 'TF_BACKEND_CONFIG'),
                    file(credentialsId: 'terraform-tfvars-academy', variable: 'TF_VARS_FILE'),
                    string(credentialsId: 'grafana-admin-password', variable: 'TF_VAR_grafana_admin_password')
                ]) {
                    sh '''#!/usr/bin/env bash
set +x
set -euo pipefail
export AWS_PAGER=''
export AWS_CONFIG_FILE=/dev/null
export AWS_EC2_METADATA_DISABLED=true
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN
unset AWS_PROFILE AWS_DEFAULT_PROFILE AWS_ROLE_ARN AWS_WEB_IDENTITY_TOKEN_FILE
plan_file="$WORKSPACE/.terraform-bootstrap.tfplan"
summary_file="$WORKSPACE/terraform-bootstrap-summary.txt"
rm -f -- "$plan_file" "$summary_file"
terraform -chdir=platform/terraform plan -input=false -lock-timeout=5m \
  -var-file="$TF_VARS_FILE" \
  -target=module.eks \
  -target=aws_ecr_repository.events_app \
  -target=aws_ecr_lifecycle_policy.events_app \
  -out="$plan_file"
terraform -chdir=platform/terraform show -no-color "$plan_file" \
  | sed -n -E '/^  # /p;/^Plan:/p' | tee "$summary_file"
if terraform -chdir=platform/terraform show -json "$plan_file" \
  | jq -e '[.resource_changes[]? | select(.change.actions | index("delete"))] | length > 0' >/dev/null; then
  echo 'ERROR: Bootstrap plan contains delete/replace actions. Investigation is required; no approval or apply will be offered.' >&2
  exit 1
fi
'''
                }
            }
        }

        stage('Approve Terraform bootstrap') {
            when {
                beforeAgent true
                expression { terraformProvisioningRequested() }
            }
            steps {
                script {
                    def summary = readFile('terraform-bootstrap-summary.txt').trim()
                    timeout(time: 20, unit: 'MINUTES') {
                        input message: "Review the bootstrap Terraform plan in this build.\n\n${summary}\n\nApply this exact EKS/ECR bootstrap plan?",
                              ok: 'Apply reviewed bootstrap plan'
                    }
                }
            }
        }

        stage('Terraform bootstrap apply') {
            when {
                beforeAgent true
                expression { terraformProvisioningRequested() }
            }
            steps {
                withCredentials([
                    file(credentialsId: 'aws-academy-credentials', variable: 'AWS_SHARED_CREDENTIALS_FILE'),
                    file(credentialsId: 'terraform-tfvars-academy', variable: 'TF_VARS_FILE'),
                    string(credentialsId: 'grafana-admin-password', variable: 'TF_VAR_grafana_admin_password')
                ]) {
                    sh '''#!/usr/bin/env bash
set +x
set -euo pipefail
export AWS_PAGER=''
export AWS_CONFIG_FILE=/dev/null
export AWS_EC2_METADATA_DISABLED=true
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN
unset AWS_PROFILE AWS_DEFAULT_PROFILE AWS_ROLE_ARN AWS_WEB_IDENTITY_TOKEN_FILE
plan_file="$WORKSPACE/.terraform-bootstrap.tfplan"
test -f "$plan_file" || { echo 'ERROR: Reviewed bootstrap plan is missing; refusing to create a new plan during apply.' >&2; exit 1; }
terraform -chdir=platform/terraform apply -input=false -lock-timeout=5m "$plan_file"
'''
                }
            }
        }

        stage('Verify Terraform infrastructure readiness') {
            options { timeout(time: 25, unit: 'MINUTES') }
            when {
                beforeAgent true
                expression { terraformProvisioningRequested() }
            }
            steps {
                withCredentials([file(credentialsId: 'aws-academy-credentials', variable: 'AWS_SHARED_CREDENTIALS_FILE')]) {
                    sh '''#!/usr/bin/env bash
set +x
set -euo pipefail
export AWS_PAGER=''
export AWS_CONFIG_FILE=/dev/null
export AWS_EC2_METADATA_DISABLED=true
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN
unset AWS_PROFILE AWS_DEFAULT_PROFILE AWS_ROLE_ARN AWS_WEB_IDENTITY_TOKEN_FILE
cluster=$(terraform -chdir=platform/terraform output -raw eks_cluster_name)
region=$(terraform -chdir=platform/terraform output -raw region)
registry=$(terraform -chdir=platform/terraform output -raw ecr_registry)
aws sts get-caller-identity --region "$region" >/dev/null || { echo 'ERROR: AWS Academy credentials expired before readiness verification.' >&2; exit 1; }
aws eks wait cluster-active --name "$cluster" --region "$region"
test "$(aws eks describe-cluster --name "$cluster" --region "$region" --query 'cluster.status' --output text)" = ACTIVE
nodegroups=$(aws eks list-nodegroups --cluster-name "$cluster" --region "$region" --query 'nodegroups[]' --output text)
test -n "$nodegroups" || { echo 'ERROR: EKS cluster has no managed node groups.' >&2; exit 1; }
for nodegroup in $nodegroups; do aws eks wait nodegroup-active --cluster-name "$cluster" --nodegroup-name "$nodegroup" --region "$region"; done
aws ecr describe-repositories --repository-names events-app --region "$region" --query 'repositories[0].repositoryUri' --output text | grep -Fx "$registry/events-app" >/dev/null
export KUBECONFIG
KUBECONFIG=$(mktemp)
trap 'rm -f -- "$KUBECONFIG"' EXIT
aws eks update-kubeconfig --name "$cluster" --region "$region" --kubeconfig "$KUBECONFIG" >/dev/null
kubectl --kubeconfig "$KUBECONFIG" wait --for=condition=Ready nodes --all --timeout=15m
kubectl --kubeconfig "$KUBECONFIG" get nodes -o wide
'''
                }
            }
        }

        stage('Terraform platform plan') {
            when {
                beforeAgent true
                expression { terraformProvisioningRequested() }
            }
            steps {
                withCredentials([
                    file(credentialsId: 'aws-academy-credentials', variable: 'AWS_SHARED_CREDENTIALS_FILE'),
                    file(credentialsId: 'terraform-tfvars-academy', variable: 'TF_VARS_FILE'),
                    string(credentialsId: 'grafana-admin-password', variable: 'TF_VAR_grafana_admin_password')
                ]) {
                    sh '''#!/usr/bin/env bash
set +x
set -euo pipefail
export AWS_PAGER=''
export AWS_CONFIG_FILE=/dev/null
export AWS_EC2_METADATA_DISABLED=true
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN
unset AWS_PROFILE AWS_DEFAULT_PROFILE AWS_ROLE_ARN AWS_WEB_IDENTITY_TOKEN_FILE
plan_file="$WORKSPACE/.terraform-platform.tfplan"
summary_file="$WORKSPACE/terraform-platform-summary.txt"
rm -f -- "$plan_file" "$summary_file"
terraform -chdir=platform/terraform plan -input=false -lock-timeout=5m -var-file="$TF_VARS_FILE" -out="$plan_file"
terraform -chdir=platform/terraform show -no-color "$plan_file" \
  | sed -n -E '/^  # /p;/^Plan:/p' | tee "$summary_file"
if terraform -chdir=platform/terraform show -json "$plan_file" \
  | jq -e '[.resource_changes[]? | select(.change.actions | index("delete"))] | length > 0' >/dev/null; then
  echo 'ERROR: Platform plan contains delete/replace actions. Investigation is required; no approval or apply will be offered.' >&2
  exit 1
fi
'''
                }
            }
        }

        stage('Approve Terraform platform') {
            when {
                beforeAgent true
                expression { terraformProvisioningRequested() }
            }
            steps {
                script {
                    def summary = readFile('terraform-platform-summary.txt').trim()
                    timeout(time: 20, unit: 'MINUTES') {
                        input message: "Review the platform Terraform plan in this build.\n\n${summary}\n\nApply this exact platform plan?",
                              ok: 'Apply reviewed platform plan'
                    }
                }
            }
        }

        stage('Terraform platform apply') {
            when {
                beforeAgent true
                expression { terraformProvisioningRequested() }
            }
            steps {
                withCredentials([
                    file(credentialsId: 'aws-academy-credentials', variable: 'AWS_SHARED_CREDENTIALS_FILE'),
                    file(credentialsId: 'terraform-tfvars-academy', variable: 'TF_VARS_FILE'),
                    string(credentialsId: 'grafana-admin-password', variable: 'TF_VAR_grafana_admin_password')
                ]) {
                    sh '''#!/usr/bin/env bash
set +x
set -euo pipefail
export AWS_PAGER=''
export AWS_CONFIG_FILE=/dev/null
export AWS_EC2_METADATA_DISABLED=true
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN
unset AWS_PROFILE AWS_DEFAULT_PROFILE AWS_ROLE_ARN AWS_WEB_IDENTITY_TOKEN_FILE
plan_file="$WORKSPACE/.terraform-platform.tfplan"
test -f "$plan_file" || { echo 'ERROR: Reviewed platform plan is missing; refusing to create a new plan during apply.' >&2; exit 1; }
terraform -chdir=platform/terraform apply -input=false -lock-timeout=5m "$plan_file"
'''
                }
            }
        }

        stage('Image Docker') {
            when { expression { env.DEPLOY == 'true' || params.LOCAL_DEMO } }
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
            when { expression { env.DEPLOY == 'true' || params.LOCAL_DEMO } }
            steps {
                script {
                    def exitCode = (env.SECURITY_GATE == 'strict') ? '1' : '0'
                    sh """
                      docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                        -v "\$DOCKER_WORKSPACE:/reports" -v trivy-cache:/root/.cache ${TRIVY_IMAGE} image \
                        --severity CRITICAL --ignore-unfixed --exit-code ${exitCode} \
                        --ignorefile /reports/.trivyignore \
                        --format table --output /reports/trivy-image.txt ${IMAGE}
                    """
                    sh 'cat trivy-image.txt'
                    if (params.LOCAL_DEMO) {
                        sh 'docker image inspect "$IMAGE" --format "{{.Id}} {{join .RepoTags \",\"}}" > local-image.txt'
                    }
                }
            }
        }

        // ------------------------------------------------------------ 10
        stage('Local demo deployment') {
            when { expression { params.LOCAL_DEMO } }
            steps {
                withCredentials([string(credentialsId: 'local-demo-mysql-password', variable: 'LOCAL_DEMO_MYSQL_PASSWORD')]) {
                    sh '''#!/usr/bin/env bash
set +x
set -euo pipefail
env_file=$(mktemp)
trap 'rm -f -- "$env_file"' EXIT
printf 'MYSQL_ROOT_PASSWORD=%s\n' "$LOCAL_DEMO_MYSQL_PASSWORD" > "$env_file"
chmod 600 "$env_file"
EVENTS_APP_IMAGE="$IMAGE" docker compose --project-name feedback-local --env-file "$env_file" up -d --no-build
for attempt in $(seq 1 30); do
  if curl -fsS --max-time 5 http://host.docker.internal:9090/events/actuator/health/readiness >/dev/null; then
    echo 'Local application is ready.'
    exit 0
  fi
  sleep 2
done
echo 'ERROR: Local application did not become ready within 60 seconds.' >&2
docker compose --project-name feedback-local ps >&2 || true
exit 1
'''
                }
            }
        }

        stage('Push image · Amazon ECR') {
            when { expression { env.DEPLOY == 'true' } }
            steps {
                script {
                    // SECURITY: scope this credential to a trusted publishing job/folder
                    // and isolated agent/Docker daemon. 'when' is not a trust boundary.
                    def pushToEcr = {
                        sh(label: 'Authenticate and push to ECR', script: '''#!/usr/bin/env bash
set +x
set -euo pipefail
: "${AWS_REGION:?AWS_REGION must be configured before the build}"
: "${ECR_REGISTRY:?ECR_REGISTRY must be configured before the build}"
: "${IMAGE:?IMAGE must be configured before the build}"
export AWS_PAGER=''
# Use the default file profile or IMDS, without inherited credential/profile overrides.
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN
unset AWS_PROFILE AWS_DEFAULT_PROFILE
unset AWS_ROLE_ARN AWS_WEB_IDENTITY_TOKEN_FILE AWS_CONTAINER_CREDENTIALS_RELATIVE_URI
unset AWS_CONTAINER_CREDENTIALS_FULL_URI AWS_CONTAINER_AUTHORIZATION_TOKEN AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE
export DOCKER_CONFIG
DOCKER_CONFIG=$(mktemp -d)
cleanup() {
    status=$?
    trap - EXIT
    docker logout "$ECR_REGISTRY" >/dev/null 2>&1 || true
    rm -rf -- "$DOCKER_CONFIG"
    exit "$status"
}
trap cleanup EXIT
if ! account=$(aws sts get-caller-identity --region "$AWS_REGION" --query Account --output text); then
    echo 'ERROR: AWS authentication failed. Check the selected credentials and Academy session expiry.' >&2
    exit 1
fi
if [[ "$ECR_REGISTRY" != "$account.dkr.ecr.$AWS_REGION.amazonaws.com" ]]; then
    echo 'ERROR: ECR_REGISTRY does not match the authenticated AWS account and region.' >&2
    exit 1
fi
if [[ "$IMAGE" != "$ECR_REGISTRY/events-app:"* ]]; then
    echo 'ERROR: IMAGE must already be tagged for ECR_REGISTRY/events-app before this stage.' >&2
    exit 1
fi
if ! aws ecr describe-repositories --region "$AWS_REGION" --repository-names events-app >/dev/null; then
    echo 'ERROR: Cannot access the events-app ECR repository. Check its existence and permissions.' >&2
    exit 1
fi
# pipefail ensures an AWS token failure cannot be hidden by docker login succeeding.
if ! aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY"; then
    echo 'ERROR: ECR authentication failed.' >&2
    exit 1
fi
if ! docker push "$IMAGE"; then
    echo 'ERROR: Docker push to ECR failed.' >&2
    exit 1
fi
''')
                    }
                    def authMode = env.AWS_AUTH_MODE ?: 'academy'
                    if (authMode == 'academy') {
                        withCredentials([file(credentialsId: 'aws-academy-credentials',
                                              variable: 'AWS_SHARED_CREDENTIALS_FILE')]) {
                            withEnv(['AWS_CONFIG_FILE=/dev/null', 'AWS_EC2_METADATA_DISABLED=true']) {
                                pushToEcr()
                            }
                        }
                    } else if (authMode == 'instance-role') {
                        // Future EC2 deployment: use IMDS, without a Jenkins AWS secret.
                        withEnv(['AWS_SHARED_CREDENTIALS_FILE=/dev/null', 'AWS_CONFIG_FILE=/dev/null',
                                 'AWS_EC2_METADATA_DISABLED=false']) {
                            pushToEcr()
                        }
                    } else {
                        error 'AWS_AUTH_MODE must be academy or instance-role.'
                    }
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

        // ------------------------------------------------------------ 12
        stage('Promotion GitOps') {
            when { expression { env.DEPLOY == 'true' } }
            steps {
                withCredentials([usernamePassword(credentialsId: env.FEATURE_SLUG == 'feedback' ? 'events-github-read' : 'github-credentials',
                                                  usernameVariable: 'GIT_USER', passwordVariable: 'GIT_TOKEN')]) {
                    // Jenkins ne déploie pas : il décrit l'état voulu sur la branche gitops.
                    // L'ApplicationSet Argo CD crée automatiquement l'environnement s'il est nouveau.
                    sh '''
                      set +x
                      set -eu
                      # Never allow a promotion to overwrite an application branch.
                      [ "$GITOPS_BRANCH" = gitops ] || { echo 'Expected GitOps branch gitops'; exit 1; }
                      if [ "$FEATURE_SLUG" = feedback ]; then
                        [ "$ENV_NAME" = feedback ] && [ "$K8S_NAMESPACE" = events-feedback ] || exit 1
                      fi
                      rm -rf gitops-work
                      AUTH_HEADER="AUTHORIZATION: basic $(printf '%s' "$GIT_USER:$GIT_TOKEN" | base64 | tr -d '\n')"
                      git -c http.extraheader="$AUTH_HEADER" \
                        clone --branch "$GITOPS_BRANCH" --depth 20 "https://github.com/$PLATFORM_REPO.git" gitops-work
                      trap 'cd "$WORKSPACE"; rm -rf gitops-work' EXIT
                      git -C gitops-work config http.extraheader "$AUTH_HEADER"
                      unset AUTH_HEADER
                      ENV_DIR="gitops-work/envs/$ENV_NAME"
                      mkdir -p "$ENV_DIR"
                      if [ "$FEATURE_SLUG" = feedback ]; then
                        # Argo cannot render two revisions of this same Git repository.
                        # Keep the reviewed chart and runtime values in one Feedback-only revision.
                        rm -rf "$ENV_DIR/chart"
                        cp -R platform/gitops/charts/events-app "$ENV_DIR/chart"
                        printf '%s\n' "$GIT_COMMIT" > "$ENV_DIR/chart-source-commit.txt"
                      fi

                      cat > "$ENV_DIR/config.json" <<EOF
{ "namespace": "$K8S_NAMESPACE", "profile": "$HELM_PROFILE", "owner": "$OWNER_SLUG" }
EOF
                      cat > "$ENV_DIR/values.yaml" <<EOF
# Généré par Jenkins — build #$BUILD_NUMBER — commit $GIT_SHORT — ne pas modifier à la main
feature: $FEATURE_SLUG
owner: $OWNER_SLUG
image:
  repository: $ECR_REGISTRY/$APP_NAME
  tag: $IMAGE_TAG
ingress:
  host: $APP_HOST
EOF
                      cd gitops-work
                      git config user.name  "Jenkins FST"
                      git config user.email "jenkins@fst-events.local"
                      git add "envs/$ENV_NAME"
                      if [ "$FEATURE_SLUG" = feedback ]; then
                        git diff --cached --name-only | while IFS= read -r path; do
                          case "$path" in envs/feedback/*) ;; *) echo 'Refusing unrelated GitOps changes'; exit 1 ;; esac
                        done
                      fi
                      git diff --cached --quiet || git commit -m "deploy($ENV_NAME): $IMAGE_TAG [build #$BUILD_NUMBER · $OWNER]"

                      # Plusieurs membres peuvent promouvoir en même temps : rebase puis nouvel essai
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

        // ------------------------------------------------------------ 13
        stage('Synchronisation Argo CD') {
            when { expression { env.DEPLOY == 'true' } }
            steps {
                withCredentials([string(credentialsId: 'argocd-token', variable: 'ARGOCD_AUTH_TOKEN')]) {
                    // On attend qu'Argo CD ait appliqué EXACTEMENT notre révision et que l'appli soit saine
                    sh '''
                      set +x
                      APP="events-$ENV_NAME"
                      WANTED=$(cat gitops-revision.txt)
                      for i in $(seq 1 60); do
                        J=$(argocd app get "$APP" --refresh -o json 2>/dev/null || true)
                        REV=$(echo "$J" | jq -r '(.status.sync.revisions // [.status.sync.revision]) | join(",")')
                        REV_MATCH=$(echo "$J" | jq -r --arg wanted "$WANTED" '(.status.sync.revisions // [.status.sync.revision]) | index($wanted) != null')
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

        // ------------------------------------------------------------ 14
        stage('Tests post-déploiement') {
            when { expression { env.DEPLOY == 'true' || params.LOCAL_DEMO } }
            parallel {
                stage('Smoke tests') {
                    steps {
                        sh '''#!/usr/bin/env bash
                          set -euo pipefail
                          BASE="http://$APP_HOST/events"
                          if [ "$LOCAL_DEMO" = true ]; then
                            BASE="http://host.docker.internal:9090/events"
                          fi
                          {
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
                          } | tee local-smoke.txt
                        '''
                    }
                }
                stage('DAST · OWASP ZAP') {
                    when { expression { return params.RUN_ZAP } }
                    steps {
                        script {
                            def tolerate = (env.SECURITY_GATE == 'strict') ? '' : ' || true'
                            def target = params.LOCAL_DEMO ? 'http://host.docker.internal:9090/events/' : "http://${env.APP_HOST}/events/"
                            sh """#!/usr/bin/env bash
                              set -euo pipefail
                              docker run --rm -v '${env.DOCKER_WORKSPACE}:/zap/wrk:rw' ${ZAP_IMAGE} \\
                                zap-baseline.py -t '${target}' -I -m 2 -r zap-report.html -J zap-report.json${tolerate}
                              test -s zap-report.html
                              test -s zap-report.json
                            """
                        }
                    }
                }
            }
        }
    }

    post {
        always {
            archiveArtifacts allowEmptyArchive: true,
                             artifacts: 'trivy-*.txt, .trivyignore, gitleaks-report.json, terraform-*-summary.txt, local-image.txt, local-smoke.txt, zap-report.html, zap-report.json, target/site/jacoco/**'
            sh 'if [ "$LOCAL_DEMO" = true ]; then MYSQL_ROOT_PASSWORD=unused docker compose --project-name feedback-local down || true; fi'
            sh 'docker image rm -f "$IMAGE" >/dev/null 2>&1 || true'
            // Saved plans can contain sensitive values. Summaries are archived above;
            // the ignored binary plans must not survive the build workspace.
            sh 'rm -f .terraform-bootstrap.tfplan .terraform-platform.tfplan'
        }
        success {
            script {
                if (env.DEPLOY == 'true') {
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

// The shared EKS/ECR/Argo platform is deliberately provisioned only from the
// protected integration branch. Feature, PR and main jobs retain application CI/CD
// but cannot create infrastructure merely by changing their Jenkinsfile.
def terraformProvisioningRequested() {
    return params.PROVISION_INFRASTRUCTURE && !env.CHANGE_ID && env.BRANCH_TYPE == 'develop'
}

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
    def msg = "${status} · ${env.FEATURE_SLUG} (#${env.BUILD_NUMBER}) · ${env.OWNER} · ${env.BUILD_URL}"
    try {
        slackSend(channel: '#igl5-g2-ci', color: color, message: msg)
    } catch (Exception ignored) {
        echo "Notification : ${msg}"
    }
}
