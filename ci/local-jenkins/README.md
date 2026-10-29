# Local Events Jenkins build agent

This configuration extends the existing controller; it never recreates it or
mounts its `jenkins_home`. It does not change the root Jenkinsfile or application.

## Architecture and inspection (2026-10-27)

- Existing controller: `jenkins`, Jenkins 2.568.3, Temurin 21, host URL
  `http://localhost:8083`, internal URL `http://jenkins:8080`.
- Controller volume: `jenkins_home`; networks: `bridge`, `jenkins-net`.
- Existing jobs: `Events-DevOps` (including `feature/feedback`), `Pipeline`,
  `hello world`. Initial controller executor count: 2; authentication enabled.
- New agent: `events-jenkins-agent`, internal SSH port 22 on `jenkins-net`.
  No published port, privileged mode, Docker socket, or controller-volume access.
- Build Java: Temurin 17 at `/opt/java/build-jdk17`; Maven 3.9.11.
- Remoting Java: Temurin 21 at `/opt/java/openjdk/bin/java`.
  Jenkins 2.568.3 cannot run its agent JVM on Java 17. Shell builds can use 17:
  https://www.jenkins.io/doc/book/platform-information/support-policy-java/
- Docker reported 20 CPUs, about 15.5 GiB RAM, 35 images (20.33 GB),
  12 volumes (1.109 GB), 4.935 GB build cache. No cleanup was performed.
- SonarQube and Nexus were stopped during initial inspection; both already
  belong to `jenkins-net`. SonarQube stores data/extensions/logs/temp in existing
  Docker volumes; Nexus uses its existing `/nexus-data` volume. Nexus host port
  8084 maps to container 8084, although its normal Maven HTTP service is 8081.
- Windows has Temurin 17.0.20.1; Maven is absent from PATH. The repository has a
  Maven 3.8.6 wrapper. Tests use H2; no MySQL container is needed for these tests.
- Git, Pipeline, Multibranch, GitHub Branch Source, SSH Build Agents, JUnit,
  Credentials Binding and Timestamper plugins are installed. Initial plugin
  inventory lacks `ansicolor`, `coverage`, `sonar`. Slack is optional in the
  shared Jenkinsfile because notification exceptions are caught.

## Build and start

Run from the repository root in PowerShell:

```powershell
docker compose -f ci/local-jenkins/compose.yaml build
Copy-Item ci/local-jenkins/.env.example ci/local-jenkins/.env
# Edit .env with ONLY the public SSH key for the Jenkins agent credential.
docker compose --env-file ci/local-jenkins/.env -f ci/local-jenkins/compose.yaml up -d
docker compose -f ci/local-jenkins/compose.yaml ps
docker exec -u jenkins events-jenkins-agent java -version
docker exec -u jenkins events-jenkins-agent mvn -version
docker exec -u jenkins events-jenkins-agent git --version
```

An empty public key permits tool/connectivity inspection but does not authorize
SSH logins. Set the public key and rerun `up -d` before launching the Jenkins node.
The image uses official versioned base tags pinned by repository digest; update
both tag and digest together. Apt packages remain tied to the base distribution's repositories.
Use image rebuilds for updates, never manual dependency installs in containers.

Named volumes `events-ci-agent-work`, `events-ci-maven-cache`, and
`events-ci-agent-ssh-config` persist workspace, Maven downloads, and SSH server
configuration/host keys. The upstream SSH image starts sshd as root; Jenkins
commands run as user `jenkins`. The agent has a 3 GiB memory limit and 2 CPU limit.
Use `docker compose -f ci/local-jenkins/compose.yaml stop` to stop it while
preserving all data. Never use `down -v` or prune commands for this setup.

## Secure Jenkins connection

No Jenkins credentials were read or authentication changed. Anonymous Jenkins
API access returns HTTP 403, so an authenticated administrator must do these UI
steps. Do not put a private key, password, API token, or inbound secret in chat,
Compose environment variables, project files, Docker images, or Git.

1. Obtain a dedicated SSH key pair through your normal secure key workflow.
   Keep its private key encrypted outside the repository. Put only the public
   `.pub` line in `ci/local-jenkins/.env` (ignored by the root `.gitignore`).
2. Jenkins: **Manage Jenkins > Credentials > System > Global credentials >
   Add Credentials**. Kind **SSH Username with private key**; scope **System**
   (agent use); username `jenkins`; ID `events-local-agent-ssh`. Enter the private
   key and its passphrase only in Jenkins' secure credential interface.
3. **Manage Jenkins > Nodes > New Node**: `events-jdk17`, **Permanent Agent**.
   If an inbound node was already created, edit its launch method instead.
4. Set **Number of executors** `1`, **Remote root directory**
   `/home/jenkins/agent`, **Labels** `events-jdk17 linux maven`, and **Usage**
   **Use this node as much as possible**.
5. **Launch method**: **Launch agents via SSH**; **Host**
   `events-jenkins-agent`; **Credentials** `events-local-agent-ssh`; **Port** `22`.
   Under **Advanced**, set **JavaPath** `/opt/java/openjdk/bin/java` (Java 21).
6. Use **Manually provided key verification strategy**. Read the actual public
   host key locally with:

   ```powershell
   docker exec events-jenkins-agent cat /etc/ssh/ssh_host_ed25519_key.pub
   docker exec events-jenkins-agent ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
   ```

   Paste the public host-key line into the strategy's **Key** field. Do not use
   the non-verifying strategy. Save, then **Launch agent**; confirm **Connected**.
   SSH server host keys persist across agent recreation in the dedicated volume.
7. **Manage Jenkins > Nodes > Built-In Node > Configure**: set executors to `0`,
   save. Let existing builds finish first. Verify that this is the only online
   node eligible for unlabelled jobs. This sends `agent any` builds here without
   modifying the shared Jenkinsfile. On a future multi-agent installation,
   scheduling must be reviewed again; `agent any` does not guarantee a JDK label.

The supported SSH agent mechanism is documented at
https://github.com/jenkinsci/docker-ssh-agent .

## Build-only verification through Jenkins

1. **Manage Jenkins > Plugins > Available plugins**: install **Coverage**
   (`coverage`), **AnsiColor** (`ansicolor`) and **SonarQube Scanner** (`sonar`).
   Coverage is needed for verification; all three are needed by the root pipeline.
   Check the **Installed** tab and any plugin load/dependency errors. Restart
   Jenkins only if requested by the plugin manager, after active builds finish.
2. **New Item > Pipeline**: name `Events-Local-CI-Verify`.
3. **Pipeline > Definition: Pipeline script**: paste `Jenkinsfile.verify` from
   this directory; leave **Use Groovy Sandbox** enabled. Save; **Build Now**.
   This does not require committing or pushing these infrastructure files.
4. Confirm the console runs on `events-jdk17`, displays Java 17, and checks out
   the intended `feature/feedback` revision. The checkout uses the remote branch;
   it does not include unpushed application edits. If the repository requires
   authentication, select a credential entered through Jenkins' credential UI
   and use the Pipeline Syntax generator to add its `credentialsId` to `git`.
5. Commands match the shared build stages: `versions:set` to
   `1.0.0-feedback-SNAPSHOT`, `clean compile`, then `verify`, all with `-B -ntp`.
6. Inspect **Test Result** for the expected 125 tests, zero failures/errors, and
   any skipped tests. Inspect **Couverture JaCoCo** and **Artifacts** for
   `target/site/jacoco/index.html`, `jacoco.xml`, and Surefire XML/text reports.
   Missing test/coverage files are not silently accepted by this job.

This separate job is a build-environment check. It makes no claim about Gitleaks,
Trivy, SonarQube, or deployment success and does not disable shared checks.

## Shared pipeline stages and remaining prerequisites

| Stages in root Jenkinsfile | Prerequisites / local scope |
| --- | --- |
| Contexte & garde GitFlow | Git checkout, Multibranch metadata; `feature/feedback` passes branch syntax. |
| Build Maven; Tests & couverture | JDK 17, Maven, dependency download access, JUnit + Coverage. |
| Secrets: Gitleaks | Docker CLI **and daemon**, image `zricethezav/gitleaks:v8.21.2`, complete checkout and writable report mount. |
| Dependencies & IaC: Trivy FS | Docker CLI/daemon, `aquasec/trivy:0.56.2`, vulnerability DB download/cache and writable report mount. Existing `--exit-code 0` is the shared report policy; unchanged. |
| Analyse SonarQube | `sonar` plugin, named server `sonarqube`, credential `sonar-token`, project creation/analysis rights, scanner Maven plugin `3.11.0.3922`. |
| Quality Gate | SonarQube webhook to Jenkins `/sonarqube-webhook/`, including trailing slash; successful scanner task association and reachable callback. |
| Publication JAR: Nexus | Beyond this build-only check: `NEXUS_URL`, Nexus repositories and `nexus-credentials`, `ci/maven-settings.xml`. |
| Image Docker; Scan image: Trivy | Docker build daemon, aligned workspace mounts, image access and `.trivyignore`. |
| Push image: Amazon ECR | Out of scope: AWS CLI, IAM/ECR and region/registry. |
| Approbation production | Main branch manual input; no local changes. |
| Promotion GitOps | Out of scope: GitHub credentials, platform repository, GitOps branch and permission to push. |
| Synchronisation Argo CD | Out of scope: Argo CD CLI/server/token and `jq`. |
| Tests post-deploiement: Smoke/ZAP | Out of scope: deployed application DNS/routing, curl, Docker/ZAP. |
| Global post | Archives reports; attempts Docker image cleanup; optional Slack notification. |

Do **not** trigger the full `feature/feedback` pipeline expecting CI-only
behavior: the root Jenkinsfile sets `DEPLOY=true` for feature branches. Its
existing PR behavior also needs valid Multibranch metadata; do not fake it to
bypass deployment. No shared Jenkinsfile edits are required for this agent.

Native Gitleaks/Trivy executables alone would not satisfy the current Docker
commands. This agent deliberately has no Docker daemon/socket/CLI. Mounting
`/var/run/docker.sock` would let builds control Docker Desktop, including reading
or deleting other containers and volumes, and requires explicit user approval.
Docker-in-Docker also needs a separately reviewed privilege/network/storage
design. Neither has been configured here. With any external daemon, bind source
`$WORKSPACE` is resolved by the **daemon**, not inside the agent: simply mounting
the socket would not make the agent's named-volume workspace available at that
same daemon-host path. Report mounts must be designed and validated first.

## SonarQube and Nexus checks

The existing SonarQube container can be started with `docker start sonarqube`;
this preserves its existing volumes. Do not replace it. Check from the agent:

```powershell
docker exec -u jenkins events-jenkins-agent curl -fsS http://jenkins:8080/login
docker exec -u jenkins events-jenkins-agent curl -fsS http://sonarqube:9000/api/system/status
```

HTTP reachability does not prove authorization or Quality Gate configuration.
In Jenkins **Manage Jenkins > System > SonarQube servers**, enable environment
injection as required, add name `sonarqube`, URL `http://sonarqube:9000`, and
select `sonar-token` (Secret text, entered only in Jenkins). In SonarQube
**Administration > Configuration > Webhooks > Create**, use name
`jenkins-local` and URL `http://jenkins:8080/sonarqube-webhook/`. If webhook signing
is enabled, store the matching secret through the secure Jenkins/SonarQube UI
and configure the Jenkins server's webhook credential. Verify a real delivery
and Quality Gate after scanner execution; do not fabricate task status.

Nexus is unnecessary for `clean compile`/`verify` with Maven Central. When
publication is intentionally in scope later, verify `http://nexus:8081` from the
agent and actual repository availability, rather than assuming host port 8084
serves the Maven API. Leave Nexus and unrelated containers untouched for now.
