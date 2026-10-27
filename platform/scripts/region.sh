#!/usr/bin/env bash
# Région AWS commune aux scripts (sourcé, non exécutable seul).
# Ordre : AWS_REGION (exportée par le Makefile), AWS_DEFAULT_REGION,
# région de la configuration AWS CLI, puis eu-west-3.

resolve_region() {
  local region="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
  if [[ -z "$region" ]] && command -v aws >/dev/null; then
    region="$(aws configure get region 2>/dev/null || true)"
  fi
  printf '%s\n' "${region:-eu-west-3}"
}

# Arrête le script si le contexte kubectl courant (ARN EKS) ou l'état Terraform
# désignent une autre région que $1 : on n'agit jamais sur le mauvais cluster.
check_region_consistency() {
  local region="$1" terraform_dir="${2:-}" context_cluster cluster_region tf_region
  context_cluster="$(kubectl config view --minify -o jsonpath='{.contexts[0].context.cluster}' 2>/dev/null || true)"
  if [[ "$context_cluster" =~ ^arn:aws[a-z-]*:eks:([a-z0-9-]+):[0-9]+:cluster/ ]]; then
    cluster_region="${BASH_REMATCH[1]}"
    if [[ "$cluster_region" != "$region" ]]; then
      printf 'Contexte kubectl en %s mais région attendue %s : lancez « make kubeconfig » ou exportez AWS_REGION.\n' \
        "$cluster_region" "$region" >&2
      return 1
    fi
  else
    printf 'Avertissement : contexte kubectl « %s » sans ARN EKS, région non vérifiable.\n' "${context_cluster:-aucun}" >&2
  fi
  if [[ -n "$terraform_dir" ]] && command -v terraform >/dev/null; then
    tf_region="$(terraform -chdir="$terraform_dir" output -raw region 2>/dev/null || true)"
    if [[ "$tf_region" =~ ^[a-z]{2}(-[a-z]+)+-[0-9]$ && "$tf_region" != "$region" ]]; then
      printf 'État Terraform en %s mais région attendue %s : alignez AWS_REGION sur terraform.tfvars.\n' \
        "$tf_region" "$region" >&2
      return 1
    fi
  fi
  printf 'Région AWS : %s\n' "$region"
}
