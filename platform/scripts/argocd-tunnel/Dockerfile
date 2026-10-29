# Local-only helper, separate from Jenkins. No host ports are published.
FROM public.ecr.aws/aws-cli/aws-cli:2.38.4
ARG KUBECTL_VERSION=v1.34.1
USER root
RUN curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
 && curl -fsSLo /tmp/kubectl.sha256 "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256" \
 && echo "$(cat /tmp/kubectl.sha256)  /usr/local/bin/kubectl" | sha256sum -c - \
 && chmod 755 /usr/local/bin/kubectl \
 && rm /tmp/kubectl.sha256
COPY entrypoint.sh /usr/local/bin/events-tunnel
RUN chmod 755 /usr/local/bin/events-tunnel && mkdir /work && chown 1000:1000 /work
USER 1000:1000
ENV HOME=/work KUBECONFIG=/work/kubeconfig AWS_PAGER=""
ENTRYPOINT ["/usr/local/bin/events-tunnel"]
