#!/bin/sh
set -eu
: "${AWS_REGION:?Set AWS_REGION}"
: "${EKS_CLUSTER_NAME:?Set EKS_CLUSTER_NAME}"
: "${AWS_SHARED_CREDENTIALS_FILE:?Mount a dedicated AWS shared-credentials file at /aws/credentials}"

if ! aws sts get-caller-identity --region "$AWS_REGION" >/dev/null; then
  echo "ERROR: AWS Academy authentication failed or expired. Refresh the dedicated tunnel credentials file, then restart events-argocd-tunnel." >&2
  exit 78
fi

if ! aws eks update-kubeconfig --region "$AWS_REGION" --name "$EKS_CLUSTER_NAME" >/dev/null; then
  echo "ERROR: Cannot create kubeconfig for EKS cluster $EKS_CLUSTER_NAME in $AWS_REGION." >&2
  exit 1
fi
# 0.0.0.0 is ONLY the isolated Docker network. Never publish this port on the host.
# kubectl authenticates to EKS; Argo still requires its own API token.
exec kubectl -n argocd port-forward --address 0.0.0.0 service/argocd-server 8080:80
