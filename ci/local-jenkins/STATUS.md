# Local verification status — 2026-10-27

## Confirmed

- Existing Jenkins controller remains running on port 8083, version 2.568.3,
  with its original `jenkins_home` volume. Authentication was not modified.
- Built image: `events-jenkins-agent:jdk17-maven3.9.11`.
- New agent container is healthy, non-privileged, on `jenkins-net`, with no host
  port bindings and no Docker socket mount.
- Build tools executed as user `jenkins`: Temurin **17.0.17+10**, Maven **3.9.11**,
  Git **2.47.3**. Remoting Java is Temurin **21.0.11+10**.
- Agent → Jenkins `/login`: HTTP **200**. Controller → agent port 22: TCP
  connection succeeded. This is transport verification, not authenticated
  Jenkins node registration.
- Agent and controller → SonarQube `/api/system/status`: **UP**, version
  **26.9.0.129388**. Existing SonarQube container was started with its original
  volumes. Nexus and unrelated containers were left stopped.
- Agent SSH host fingerprint (ED25519):
  `SHA256:tljfpihitju0RH3bC4EsxSQkvpCl8HlMP+VxDyXUPTM`.
  Obtain its public key using the README command when configuring verification.
- An isolated remote checkout on the agent matches local branch HEAD:
  `a8ba9d64e0b845128d1311d3a3a710a80c7b8cbb`.
- Compose configuration validation passed; the agent shell file has LF endings.
- SSH effective configuration: root login, password authentication, and keyboard
  interactive authentication are disabled; public-key authentication is used.
- Changes are restricted to this infrastructure directory. No commits or pushes.

## Actual agent-side Maven result (not a Jenkins build)

Executed as `jenkins` in `/home/jenkins/agent/local-tool-verification`:

```text
mvn -B -ntp versions:set -DnewVersion=1.0.0-feedback-SNAPSHOT -DgenerateBackupPoms=false
mvn -B -ntp clean compile
mvn -B -ntp verify
```

All three commands completed successfully. Surefire XML totals:
**125 tests, 0 failures, 0 errors, 0 skipped**. JaCoCo analyzed 20 classes.
The Spring Boot executable JAR was produced.

| JaCoCo metric | Covered | Missed | Coverage |
| --- | ---: | ---: | ---: |
| Instructions | 1110 | 898 | 55.28% |
| Branches | 58 | 32 | 64.44% |
| Lines | 231 | 124 | 65.07% |
| Methods | 81 | 23 | 77.88% |
| Classes | 18 | 2 | 90.00% |

Reports remain in the agent's persistent workspace and were copied to the
ignored host directory `target/local-jenkins-verification/`:
`surefire-reports/`, `jacoco/jacoco.xml`, and `jacoco/index.html`.
These reports were **not published or archived by Jenkins**.

## Pending authenticated Jenkins work

Anonymous Jenkins API access returns **403**. No Jenkins password, private key,
or API token was obtained or extracted from its storage.

The node is **not connected to Jenkins yet**. An administrator must add its SSH
credential through Jenkins' secure UI and configure the node as in README.md.
The public login key was left empty; the container authorizes no supplied key.
Controller executors are still at their original value (2).

Initial installed plugin inventory lacks **AnsiColor**, **Coverage**, and
**SonarQube Scanner**. Their installation and active state remain unverified.

No Jenkins verification build has run, and Jenkins test/coverage publication is
**not verified**. Use the separate `Jenkinsfile.verify` after node/plugin setup.

## Security and full-pipeline readiness

Gitleaks and Trivy were not run. Their shared pipeline stages require Docker CLI
and daemon access plus correct workspace/report mount paths. No Docker socket
access has been granted. SonarQube server configuration, analysis token, project
rights, webhook delivery, scanner execution and Quality Gate remain unverified.

The unchanged shared Jenkinsfile enables deployment for `feature/feedback` and
continues into Nexus, image publication, ECR, GitOps, Argo CD and deployed-app
tests. Cloud/deployment configuration is deliberately outside this local task.
