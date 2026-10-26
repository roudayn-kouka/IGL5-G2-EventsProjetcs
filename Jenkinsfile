// Pipeline Events · FST · IGL5 G2 — feature logistics sur AWS (Terraform, ECR, EKS, Argo CD)
// Adapté du Jenkinsfile de Roudayna.

pipeline {
  agent any
  tools { maven 'Maven3'; jdk 'JDK17' }

  options {
    timestamps()
    timeout(time: 60, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '15', artifactNumToKeepStr: '5'))
    disableConcurrentBuilds()
  }

  environment {
    APP_NAME   = 'events-app'
    MVN        = 'mvn -B -ntp'
    AWS_REGION = 'us-east-1'
    CLUSTER    = 'fst-events'
    PLATFORM   = 'AhlemMastouri/Events-Platform'
    ECR_REPO = '155368763737.dkr.ecr.us-east-1.amazonaws.com/events-app'  // terraform output ecr_url
    ARGO_URL   = 'https://HOTE-ARGOCD.us-east-1.elb.amazonaws.com'           // EXTERNAL-IP argocd-server
    APP_BASE   = 'http://HOTE-APP.us-east-1.elb.amazonaws.com/events'        // EXTERNAL-IP events-app
  }

  stages {

    stage('1 · Contexte & garde GitFlow') {
      steps {
        script {
          def branch = env.CHANGE_BRANCH ?: env.BRANCH_NAME
          if (!(branch ==~ /^(main|develop|feature\/[a-z0-9-]+|release\/\d+\.\d+(\.\d+)?|hotfix\/[a-z0-9.-]+)$/)) {
            error "Nom de branche '${branch}' hors convention GitFlow"
          }
          if (env.CHANGE_ID && branch.startsWith('feature/') && env.CHANGE_TARGET != 'develop') {
            error "GitFlow : une feature se fusionne dans develop, pas dans ${env.CHANGE_TARGET}"
          }

          env.BRANCH_TYPE   = env.CHANGE_ID ? 'pr' : branchType(branch)
          env.FEATURE_SLUG  = featureSlug(branch)
          env.OWNER         = ownerOf(branch)
          env.OWNER_SLUG    = slugify(env.OWNER)
          env.GIT_SHORT     = sh(script: 'git rev-parse --short=7 HEAD', returnStdout: true).trim()
          env.ENV_NAME      = envName(env.BRANCH_TYPE, env.FEATURE_SLUG)
          env.DEPLOY        = (env.BRANCH_TYPE == 'feature') ? 'true' : 'false'
          env.SECURITY_GATE = (env.BRANCH_TYPE in ['main', 'release']) ? 'strict' : 'report'
          env.APP_VERSION   = (env.BRANCH_TYPE == 'main') ? "1.0.${env.BUILD_NUMBER}" : "1.0.0-${env.FEATURE_SLUG}-SNAPSHOT"
          env.IMAGE_TAG     = "${env.FEATURE_SLUG}-${env.BUILD_NUMBER}-${env.GIT_SHORT}"
          env.IMAGE         = "${env.ECR_REPO}:${env.IMAGE_TAG}"
          env.SONAR_KEY     = "fst-events-${env.FEATURE_SLUG}"

          currentBuild.displayName = "#${env.BUILD_NUMBER} · ${env.FEATURE_SLUG}"
          currentBuild.description = "${env.OWNER} · ${env.GIT_SHORT} · events-${env.ENV_NAME}"

          echo """
          ┌──────────────── Contexte ────────────────
          │ Branche       : ${branch} (${env.BRANCH_TYPE})
          │ Responsable   : ${env.OWNER}
          │ Version Maven : ${env.APP_VERSION}
          │ Image         : ${env.IMAGE}
          │ Environnement : events-${env.ENV_NAME}
          │ Déploiement   : ${env.DEPLOY}
          │ Gate sécurité : ${env.SECURITY_GATE}
          └──────────────────────────────────────────"""
        }
      }
    }

    stage('2 · Build Maven') {
      steps {
        sh '$MVN versions:set -DnewVersion=$APP_VERSION -DgenerateBackupPoms=false'
        sh '$MVN clean compile'
      }
    }

    stage('3 · Tests & couverture') {
      steps { sh '$MVN verify' }
      post { always { junit allowEmptyResults: true, testResults: 'target/surefire-reports/*.xml' } }
    }

    stage('4 · Sécurité du code') {
      parallel {
        stage('4a · Secrets (Gitleaks)') {
          steps { sh 'gitleaks detect --source . --redact --report-format json --report-path gitleaks-report.json' }
        }
        stage('4b · Dépendances & IaC (Trivy FS)') {
          steps { sh 'trivy fs --scanners vuln,misconfig --severity HIGH,CRITICAL --exit-code 0 --output trivy-fs.txt .' }
        }
      }
    }

    stage('5 · Analyse SonarQube') {
      steps {
        withSonarQubeEnv('SonarQube') {
          sh '''
            $MVN org.sonarsource.scanner.maven:sonar-maven-plugin:3.10.0.2594:sonar \
              -Dsonar.projectKey=$SONAR_KEY \
              -Dsonar.projectName="Events · $FEATURE_SLUG" \
              -Dsonar.projectVersion=$APP_VERSION
          '''
        }
      }
    }

    stage('6 · Quality Gate') {
      steps { timeout(time: 10, unit: 'MINUTES') { waitForQualityGate abortPipeline: true } }
    }

    stage('Terraform (infrastructure AWS)') {
      when { expression { env.DEPLOY == 'true' } }
      steps {
        withCredentials([usernamePassword(credentialsId: 'platform-creds', usernameVariable: 'GH_USER', passwordVariable: 'GH_TOKEN'),
               string(credentialsId: 'aws_access_key_id',     variable: 'AWS_ACCESS_KEY_ID'),
string(credentialsId: 'aws_secret_access_key', variable: 'AWS_SECRET_ACCESS_KEY'),
string(credentialsId: 'aws_session_token',     variable: 'AWS_SESSION_TOKEN')]) {
          sh '''
            export AWS_DEFAULT_REGION=$AWS_REGION
            rm -rf tfrepo
            git clone --depth 1 https://${GH_USER}:${GH_TOKEN}@github.com/${PLATFORM}.git tfrepo
            cd tfrepo/terraform
            terraform init -input=false
            terraform apply -auto-approve -input=false -state=/var/jenkins_home/terraform.tfstate
            cd ../.. && rm -rf tfrepo
          '''
        }
      }
    }

    stage('7 · Publication JAR (Nexus)') {
      when { expression { env.DEPLOY == 'true' } }
      steps {
        withCredentials([usernamePassword(credentialsId: 'nexus-creds', usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASS')]) {
          sh '$MVN -s settings-ci.xml -DskipTests deploy'
        }
      }
    }

    stage('8 · Image Docker') {
      when { expression { env.DEPLOY == 'true' } }
      steps {
        sh '''
          docker build \
            --label org.opencontainers.image.revision=$GIT_SHORT \
            --label org.opencontainers.image.version=$APP_VERSION \
            --label tn.fst.feature=$FEATURE_SLUG \
            --label tn.fst.owner=$OWNER_SLUG \
            -t $IMAGE .
        '''
      }
    }

    stage('9 · Scan image (Trivy)') {
      when { expression { env.DEPLOY == 'true' } }
      steps {
        script {
          def exitCode = (env.SECURITY_GATE == 'strict') ? '1' : '0'
          def tolerate = (env.SECURITY_GATE == 'strict') ? '' : ' || true'
          sh "trivy image --timeout 30m --scanners vuln --skip-java-db-update --severity CRITICAL --ignore-unfixed --exit-code ${exitCode} --output trivy-image.txt ${env.IMAGE}${tolerate}"
        }
      }
    }    stage('10 · Push image · Amazon ECR') {
      when { expression { env.DEPLOY == 'true' } }
      steps {
        withCredentials([string(credentialsId: 'aws_access_key_id', variable: 'AWS_ACCESS_KEY_ID'),
                         string(credentialsId: 'aws_secret_access_key', variable: 'AWS_SECRET_ACCESS_KEY'),
                         string(credentialsId: 'aws_session_token', variable: 'AWS_SESSION_TOKEN')]) {

          sh '''
            export AWS_DEFAULT_REGION=$AWS_REGION
            REGISTRY=${ECR_REPO%%/*}
            aws ecr get-login-password | docker login --username AWS --password-stdin "$REGISTRY"
            docker push "$IMAGE"
            docker logout "$REGISTRY"
          '''
        }
      }
    }

    stage('11 · Approbation production') {
      when { expression { env.BRANCH_TYPE == 'main' } }
      steps {
        timeout(time: 24, unit: 'HOURS') {
          input message: "Promouvoir ${env.IMAGE_TAG} en PRODUCTION ?", ok: 'Promouvoir'
        }
      }
    }

    stage('12 · Promotion GitOps') {
      when { expression { env.DEPLOY == 'true' } }
      steps {
        withCredentials([usernamePassword(credentialsId: 'platform-creds', usernameVariable: 'GH_USER', passwordVariable: 'GH_TOKEN')]) {
          sh '''
            rm -rf platform
            git clone https://${GH_USER}:${GH_TOKEN}@github.com/${PLATFORM}.git platform
            cd platform
            ENV_DIR="gitops/envs/${ENV_NAME}"
            mkdir -p "$ENV_DIR"
            cat > "$ENV_DIR/values.yaml" <<EOF
# Généré par Jenkins - build #${BUILD_NUMBER} - commit ${GIT_SHORT} - ne pas modifier à la main
feature: ${FEATURE_SLUG}
owner: ${OWNER_SLUG}
image:
  repository: ${ECR_REPO}
  tag: ${IMAGE_TAG}
EOF
            git config user.email "jenkins@fst.local"
            git config user.name "Jenkins FST"
            git add "$ENV_DIR"
            git diff --cached --quiet || git commit -m "deploy(${ENV_NAME}): ${IMAGE_TAG} [build #${BUILD_NUMBER} · ${OWNER}]"

            PUSHED=false
            for i in 1 2 3 4 5; do
              if git push origin HEAD:main; then PUSHED=true; break; fi
              [ "$i" -lt 5 ] && git pull --rebase origin main
            done
            [ "$PUSHED" = true ] || { echo "Échec du push GitOps après 5 tentatives."; exit 1; }
          '''
        }
      }
      post { always { sh 'rm -rf platform' } }
    }

    stage('13 · Synchronisation Argo CD') {
      when { expression { env.DEPLOY == 'true' } }
      steps {
        withCredentials([string(credentialsId: 'argocd-password', variable: 'ARGO_PW')]) {
          sh '''
            APP="events-${ENV_NAME}"
            printf '{"username":"admin","password":"%s"}' "$ARGO_PW" > /tmp/login.json
            RESP=$(curl -sk -X POST "$ARGO_URL/api/v1/session" -H "Content-Type: application/json" --data-binary @/tmp/login.json)
            rm -f /tmp/login.json
            TOKEN=$(echo "$RESP" | sed -n 's/.*"token":"\\([^"]*\\)".*/\\1/p')
            if [ -z "$TOKEN" ]; then
              echo "Connexion Argo CD impossible : $(echo "$RESP" | cut -c1-120)"; exit 1
            fi

            for i in $(seq 1 60); do
              R=$(curl -sk -H "Authorization: Bearer $TOKEN" "$ARGO_URL/api/v1/applications/$APP?refresh=hard")
              if echo "$R" | grep -q "$IMAGE_TAG" \
                 && echo "$R" | grep -q '"sync":{"status":"Synced"' \
                 && echo "$R" | grep -q '"health":{"status":"Healthy"'; then
                echo "Déployé et sain : $APP avec $IMAGE_TAG"; exit 0
              fi
              if echo "$R" | grep -q "$IMAGE_TAG" && echo "$R" | grep -q '"health":{"status":"Degraded"'; then
                echo "Déploiement dégradé : voir Argo CD et les logs du pod."; exit 1
              fi
              echo "attente... ($i/60)"; sleep 10
            done
            echo "Délai dépassé (10 min)."; exit 1
          '''
        }
      }
    }

    stage('14 · Tests post-déploiement') {
      when { expression { env.DEPLOY == 'true' } }
      parallel {
        stage('14a · Smoke tests') {
          steps {
            sh '''
              for i in $(seq 1 18); do
                CODE=$(curl -s -o /dev/null -w "%{http_code}" "$APP_BASE/logistics" || true)
                echo "HTTP $CODE"
                if [ "$CODE" = "200" ]; then echo "API logistics opérationnelle."; break; fi
                if [ "$i" = "18" ]; then echo "L'application ne répond pas."; exit 1; fi
                sleep 10
              done
              H=$(curl -s -o /dev/null -w "%{http_code}" "$APP_BASE/actuator/health" || true)
              echo "Actuator health : HTTP $H (informatif tant qu'Actuator n'est pas ajouté)"
            '''
          }
        }
        stage('14b · DAST (OWASP ZAP)') {
          steps {
            script {
              def tolerate = (env.SECURITY_GATE == 'strict') ? '' : ' || true'
              sh "docker run --rm ghcr.io/zaproxy/zaproxy:stable zap-baseline.py -t ${env.APP_BASE}/logistics -I -m 2${tolerate}"
            }
          }
        }
      }
    }
  }

  post {
    always {
      archiveArtifacts allowEmptyArchive: true, artifacts: 'trivy-*.txt, gitleaks-report.json, target/site/jacoco/**'
      sh 'docker image rm -f "$IMAGE" >/dev/null 2>&1 || true'
      script { notifyTeam(currentBuild.currentResult) }
    }
  }
}

// ============================ Fonctions utilitaires ============================

def ownerOf(String branch) {
  def owners = [
    'feature/event-statistics': 'Roudayna Kouka',
    'feature/participant'     : 'Farah Baraket',
    'feature/logistics'       : 'Ahlem Mastouri',
    'feature/event'           : 'Nour Mustapha',
    'feature/feedback'        : 'Emna Ouarteni',
  ]
  return owners[branch] ?: 'Equipe IGL5-G2'
}

def branchType(String branch) {
  if (branch == 'main')              return 'main'
  if (branch == 'develop')           return 'develop'
  if (branch.startsWith('release/')) return 'release'
  if (branch.startsWith('hotfix/'))  return 'hotfix'
  return 'feature'
}

def featureSlug(String branch) {
  if (branch == 'main')    return 'prod'
  if (branch == 'develop') return 'staging'
  return slugify(branch.replaceFirst(/^(feature|release|hotfix)\//, ''))
}

def envName(String type, String slug) {
  if (type == 'main') return 'prod'
  if (type in ['develop', 'release', 'hotfix']) return 'staging'
  return slug
}

def slugify(String s) {
  def out = s.toLowerCase().replaceAll(/[^a-z0-9]+/, '-').replaceAll(/^-+|-+$/, '')
  return out.length() > 40 ? out.substring(0, 40).replaceAll(/-+$/, '') : out
}

def notifyTeam(String status) {
  try {
    withCredentials([string(credentialsId: 'slack-webhook', variable: 'SLACK_URL')]) {
      withEnv(["MSG=${status} | ${env.FEATURE_SLUG ?: 'n/a'} #${env.BUILD_NUMBER} | ${env.OWNER ?: ''} | ${env.BUILD_URL}"]) {
        sh '''
          printf '{"text":"%s"}' "$MSG" > /tmp/slack.json
          curl -s -X POST -H 'Content-type: application/json' --data-binary @/tmp/slack.json "$SLACK_URL" || true
          rm -f /tmp/slack.json
        '''
      }
    }
  } catch (Exception e) {
    echo "Notification ignorée (slack-webhook absent ?) : ${status}"
  }
}