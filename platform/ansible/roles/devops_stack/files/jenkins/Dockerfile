# Jenkins LTS + outillage du pipeline : Maven, Docker CLI, AWS CLI, Argo CD CLI, jq
# (plus de kubectl ni de Helm : en GitOps, Jenkins ne touche jamais au cluster)
FROM jenkins/jenkins:2.479.3-lts-jdk17

USER root
ARG ARGOCD_VERSION=v2.13.3

RUN apt-get update \
 && apt-get install -y --no-install-recommends maven curl unzip jq ca-certificates \
 && rm -rf /var/lib/apt/lists/*

COPY --from=docker:27.3.1-cli /usr/local/bin/docker /usr/local/bin/docker

RUN curl -fsSLo /tmp/awscli.zip "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
 && unzip -q /tmp/awscli.zip -d /tmp && /tmp/aws/install && rm -rf /tmp/aws /tmp/awscli.zip \
 && curl -fsSLo /usr/local/bin/argocd "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64" \
 && chmod +x /usr/local/bin/argocd

USER jenkins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
