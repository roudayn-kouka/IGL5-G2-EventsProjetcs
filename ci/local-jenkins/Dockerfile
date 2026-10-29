ARG MAVEN_IMAGE=maven:3.9.11-eclipse-temurin-17@sha256:e4a7ace3dc0d645ed97f8d9ad0b0d3f0b14fa8d150138f27f116d7105a639b82
ARG AGENT_IMAGE=jenkins/ssh-agent:8.7.0-jdk21@sha256:30dfc3290265acfca1738fab75c1fa7c6af5731f6a6aaf37cbe0306aa50cfc5b
FROM ${MAVEN_IMAGE} AS build_tools
FROM ${AGENT_IMAGE}

USER root
COPY --from=build_tools /opt/java/openjdk /opt/java/build-jdk17
COPY --from=build_tools /usr/share/maven /usr/share/maven
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git jq unzip docker-cli \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /home/jenkins/.m2 /home/jenkins/agent \
 && chown -R jenkins:jenkins /home/jenkins/.m2 /home/jenkins/agent \
 && usermod -aG root jenkins


# Install AWS CLI v2 and Argo CD CLI
ARG TARGETARCH=amd64
ARG ARGOCD_VERSION=v3.2.0

RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) AWS_ARCH=x86_64 ;; \
      arm64) AWS_ARCH=aarch64 ;; \
      *) echo "Unsupported architecture: ${TARGETARCH}"; exit 1 ;; \
    esac; \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" -o /tmp/awscliv2.zip; \
    unzip -q /tmp/awscliv2.zip -d /tmp; \
    /tmp/aws/install; \
    rm -rf /tmp/aws /tmp/awscliv2.zip; \
    curl -fsSL "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-${TARGETARCH}" \
      -o /usr/local/bin/argocd; \
    chmod 755 /usr/local/bin/argocd; \
    aws --version; \
    argocd version --client
# Jenkins remoting is launched explicitly with /opt/java/openjdk/bin/java (21).
# Shell commands and Maven use JDK 17, independent of the remoting JVM.
ENV JAVA_HOME=/opt/java/build-jdk17 \
    MAVEN_HOME=/usr/share/maven
ENV PATH="/opt/java/build-jdk17/bin:/usr/share/maven/bin:${PATH}"
COPY --chmod=755 agent-entrypoint.sh /usr/local/bin/events-agent-entrypoint
COPY --chmod=755 mvn-wrapper.sh /opt/java/build-jdk17/bin/mvn
WORKDIR /home/jenkins/agent
ENTRYPOINT ["/usr/local/bin/events-agent-entrypoint"]
