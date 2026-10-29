#!/bin/sh
set -eu
: "${AWS_REGION:?Set AWS_REGION}"
: "${EKS_CLUSTER_NAME:?Set EKS_CLUSTER_NAME}"
aws eks update-kubeconfig --region "$AWS_REGION" --name "$EKS_CLUSTER_NAME" >/dev/null
# 0.0.0.0 is ONLY the isolated Docker network. Never publish this port on the host.
# kubectl authenticates to EKS; Argo still requires its own API token.
exec kubectl -n argocd port-forward --address 0.0.0.0 service/argocd-server 8080:80
