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
        timeout(time: 45, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '15', artifactNumToKeepStr: '5'))
        disableConcurrentBuilds()
    }

    environment {
        APP_NAME     = 'events-app'
        TRIVY_IMAGE  = 'aquasec/trivy:0.56.2'
        GITLEAKS_IMG = 'zricethezav/gitleaks:v8.21.2'
        ZAP_IMAGE    = 'ghcr.io/zaproxy/zaproxy:stable'
        SONAR_PLUGIN = 'org.sonarsource.scanner.maven:sonar-maven-plugin:5.2.0.4988'
        MVN          = 'mvn -B -ntp'
        ARGOCD_OPTS  = '--grpc-web --plaintext'
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
                    env.APP_HOST      = "${env.ENV_NAME}.${env.APPS_DOMAIN ?: 'APPS_DOMAIN-non-defini'}"

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
                    │ GitOps         : ${env.PLATFORM_REPO}@${env.GITOPS_BRANCH} · Argo CD ${env.ARGOCD_SERVER ?: '(non défini)'}
                    └──────────────────────────────────────────────────────────"""
                }
                // Prérequis du déploiement vérifiés AVANT le build : échec en quelques secondes
                // (paramètre vide, AWS/ECR, réseau, TLS, jeton, branche lue par Argo CD).
                script {
                    if (env.DEPLOY == 'true') {
                        withCredentials([string(credentialsId: 'argocd-token', variable: 'ARGOCD_AUTH_TOKEN')]) {
                            sh 'bash ci/deploy-preflight.sh'
                        }
                    }
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
                          docker run --rm -v "$WORKSPACE:/repo" $GITLEAKS_IMG detect \
                            --source /repo --redact --no-banner \
                            --report-format json --report-path /repo/gitleaks-report.json
                        '''
                    }
                }
                stage('Dépendances & IaC · Trivy FS') {
                    steps {
                        sh '''
                          docker run --rm -v "$WORKSPACE:/src" -v trivy-cache:/root/.cache $TRIVY_IMAGE fs \
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
        stage('Push image · Amazon ECR') {
            when { expression { env.DEPLOY == 'true' } }
            steps {
                // Authentification par le rôle IAM de l'EC2 : aucune clé AWS dans Jenkins
                sh '''
                  aws ecr get-login-password --region "$AWS_REGION" \
                    | docker login --username AWS --password-stdin "$ECR_REGISTRY"
                  docker push "$IMAGE"
                  docker logout "$ECR_REGISTRY"
                '''
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
                withCredentials([usernamePassword(credentialsId: 'github-credentials',
                                                  usernameVariable: 'GIT_USER', passwordVariable: 'GIT_TOKEN')]) {
                    // Jenkins ne déploie pas : il décrit l'état voulu sur la branche gitops.
                    // L'ApplicationSet Argo CD crée automatiquement l'environnement s'il est nouveau.
                    // Produit gitops-revision.txt (commit vérifié sur origin) et gitops-image.txt.
                    sh 'bash ci/gitops-promote.sh'
                }
            }
        }

        // ------------------------------------------------------------ 13
        stage('Synchronisation Argo CD') {
            when { expression { env.DEPLOY == 'true' } }
            steps {
                withCredentials([string(credentialsId: 'argocd-token', variable: 'ARGOCD_AUTH_TOKEN'),
                                 usernamePassword(credentialsId: 'github-credentials',
                                                  usernameVariable: 'GIT_USER', passwordVariable: 'GIT_TOKEN')]) {
                    // Révision de la source « values » == commit de l'étape 12 (ou descendant où
                    // envs/<env> est inchangé), image attendue présente, Synced + Healthy.
                    // Aucune erreur du CLI n'est masquée (réseau, TLS, jeton, droits, JSON).
                    sh 'bash ci/argocd-wait.sh'
                }
            }
        }

        // ------------------------------------------------------------ 14
        stage('Tests post-déploiement') {
            when { expression { env.DEPLOY == 'true' } }
            parallel {
                stage('Smoke tests') {
                    steps {
                        // Codes HTTP exacts, redirections non suivies, erreurs DNS/connexion explicites ;
                        // API métier obligatoire sur staging/prod, 404 toléré sur une feature.
                        sh 'bash ci/smoke-tests.sh'
                    }
                }
                stage('DAST · OWASP ZAP') {
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

def notifyTeam(String status, String color) {
    def msg = "${status} · ${env.FEATURE_SLUG} (#${env.BUILD_NUMBER}) · ${env.OWNER} · ${env.BUILD_URL}"
    try {
        slackSend(channel: '#igl5-g2-ci', color: color, message: msg)
    } catch (Exception ignored) {
        echo "Notification : ${msg}"
    }
}
