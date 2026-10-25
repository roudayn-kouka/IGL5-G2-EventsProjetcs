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
  }
}