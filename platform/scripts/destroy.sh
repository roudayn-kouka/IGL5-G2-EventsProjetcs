#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMEOUT_SECONDS="${DESTROY_LB_TIMEOUT_SECONDS:-900}"
POLL_SECONDS="${DESTROY_LB_POLL_SECONDS:-15}"
CLUSTER_NAME="${EKS_CLUSTER_NAME:-fst-events}"

for command_name in kubectl aws terraform; do
  command -v "$command_name" >/dev/null || { printf '%s est requis.\n' "$command_name" >&2; exit 1; }
done

echo "Désactivation de l'auto-sync des applications racine et ingress-nginx."
kubectl -n argocd patch application platform --type=merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
kubectl -n argocd patch application ingress-nginx --type=merge -p '{"spec":{"syncPolicy":{"automated":null}}}'

echo "Suppression de l'ApplicationSet events-environments et de ses applications/ressources."
kubectl -n argocd delete applicationset events-environments --cascade=foreground --wait=true

echo "Suppression du Service LoadBalancer ingress-nginx."
kubectl -n ingress-nginx delete service ingress-nginx-controller --wait=true --ignore-not-found

echo "Passage du service argocd-server en ClusterIP."
kubectl -n argocd patch service argocd-server --type=merge -p \
  '{"metadata":{"annotations":{"service.beta.kubernetes.io/aws-load-balancer-type":null,"service.beta.kubernetes.io/aws-load-balancer-internal":null}},"spec":{"type":"ClusterIP"}}'

deadline=$((SECONDS + TIMEOUT_SECONDS))
while (( SECONDS < deadline )); do
  load_balancers="$(aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerArn' --output text)"
  project_load_balancers=()
  if [[ "$load_balancers" == "None" ]]; then
    load_balancers=""
  fi
  for arn in $load_balancers; do
    cluster_tag="$(aws elbv2 describe-tags --resource-arns "$arn" \
      --query "TagDescriptions[0].Tags[?((Key=='kubernetes.io/cluster/${CLUSTER_NAME}' && (Value=='owned' || Value=='shared')) || (Key=='elbv2.k8s.aws/cluster' && Value=='${CLUSTER_NAME}'))].Key | [0]" \
      --output text)"
    if [[ "$cluster_tag" != "None" && -n "$cluster_tag" ]]; then
      project_load_balancers+=("$arn")
    fi
  done
  if [[ ${#project_load_balancers[@]} -eq 0 ]]; then
    break
  fi
  printf 'Load balancers EKS encore présents (%s) :\n' "${#project_load_balancers[@]}"
  printf '  %s\n' "${project_load_balancers[@]}"
  sleep "$POLL_SECONDS"
done

if (( SECONDS >= deadline )); then
  echo "Délai dépassé : des load balancers associés au cluster subsistent; Terraform destroy annulé." >&2
  exit 1
fi

printf 'Les load balancers EKS identifiés ont disparu. Confirmez-vous la destruction Terraform ? (oui/non) '
read -r answer
if [[ "$answer" != "oui" ]]; then
  echo "Destruction Terraform annulée."
  exit 0
fi

cd "$ROOT/terraform"
terraform destroy
