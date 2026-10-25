pipeline {
  agent any
  tools { maven 'Maven3'; jdk 'JDK17' }
  options { disableConcurrentBuilds(); timestamps() }

  stages {
    stage('1 · Contexte') {
      steps {
        script {
          if (!(env.BRANCH_NAME ==~ /(feature\/.+|develop|release\/.+|hotfix\/.+|main|PR-\d+)/)) {
            error "Branche hors GitFlow : ${env.BRANCH_NAME}"
          }
          env.FEATURE   = env.BRANCH_NAME.replaceFirst('feature/', '').replace('/', '-')
          env.SHORT_SHA = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
          env.IMAGE_TAG = "${env.FEATURE}-${env.BUILD_NUMBER}-${env.SHORT_SHA}"
          env.SONAR_KEY = "fst-events-${env.FEATURE}"
          currentBuild.displayName = "#${env.BUILD_NUMBER} · ${env.FEATURE}"
        }
      }
    }

    stage('2 · Build') {
      steps { sh 'mvn -B -DskipTests clean compile' }
    }

    stage('3 · Tests') {
      steps { sh 'mvn -B test jacoco:report' }
      post { always { junit allowEmptyResults: true, testResults: 'target/surefire-reports/*.xml' } }
    }

    stage('4 · Sécurité') {
      parallel {
        stage('4a · Secrets (Gitleaks)') {
          steps {
            sh 'gitleaks detect --source . --redact --report-format json --report-path gitleaks.json'
          }
          post { always { archiveArtifacts artifacts: 'gitleaks.json', allowEmptyArchive: true } }
        }
        stage('4b · Dépendances (Trivy)') {
          steps {
            sh 'trivy fs --severity HIGH,CRITICAL --exit-code 0 --output trivy-fs.txt .'
          }
          post { always { archiveArtifacts artifacts: 'trivy-fs.txt', allowEmptyArchive: true } }
        }
      }
    }

    stage('5 · SonarQube') {
      steps {
        withSonarQubeEnv('SonarQube') {
          sh "mvn -B sonar:sonar -Dsonar.projectKey=${env.SONAR_KEY} -Dsonar.projectName=${env.SONAR_KEY}"
        }
      }
    }

    stage('6 · Quality Gate') {
      steps {
        timeout(time: 5, unit: 'MINUTES') { waitForQualityGate abortPipeline: true }
      }
    }
        stage('7 · Publication JAR (Nexus)') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'nexus-creds',
                                          usernameVariable: 'NEXUS_USER',
                                          passwordVariable: 'NEXUS_PASS')]) {
          sh "mvn -B versions:set -DnewVersion=1.0.0-${env.FEATURE}-SNAPSHOT -DgenerateBackupPoms=false"
          sh 'mvn -B -s settings-ci.xml -DskipTests deploy'
        }
      }
    }

    stage('8 · Image Docker') {
      steps { sh "docker build -t events-app:${env.IMAGE_TAG} ." }
    }

     stage('9 · Scan image (Trivy)') {
      steps {
        sh "trivy image --timeout 30m --scanners vuln --skip-java-db-update --severity HIGH,CRITICAL --exit-code 0 --output trivy-image.txt events-app:${env.IMAGE_TAG} || true"
      }
      post { always { archiveArtifacts artifacts: 'trivy-image.txt', allowEmptyArchive: true } }
    }
         stage('10 · Envoi image (kind)') {
      steps {
        sh """
          docker save events-app:${env.IMAGE_TAG} -o /tmp/events-app.tar
          docker cp /tmp/events-app.tar fst-events-control-plane:/events-app.tar
          docker exec fst-events-control-plane ctr -n k8s.io images import --all-platforms /events-app.tar
          docker exec fst-events-control-plane rm -f /events-app.tar
          rm -f /tmp/events-app.tar
        """
      }
    }
        stage('11 · Approbation') {
      when { branch 'main' }
      steps {
        timeout(time: 24, unit: 'HOURS') {
          input message: 'Promouvoir en production ?', ok: 'Promouvoir'
        }
      }
    }     
  }
}