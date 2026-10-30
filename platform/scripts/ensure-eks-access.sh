#!/usr/bin/env bash
# Run inside Jenkins with Jenkins Credentials Manager AWS_ACCESS_KEY_ID,
# AWS_SECRET_ACCESS_KEY and AWS_SESSION_TOKEN already exported.
set -euo pipefail
export AWS_PAGER=""
REGION="${AWS_REGION:-us-east-1}"
CLUSTER="${CLUSTER:-fst-events}"
ALLOW_MISSING_EKS="${ALLOW_MISSING_EKS:-0}"

# Check AWS identity before touching the allowlist.
aws sts get-caller-identity --query Account --output text >/dev/null
MY_IP="$(curl -4fsS --connect-timeout 5 --max-time 15 https://checkip.amazonaws.com | tr -d '\r\n')"
if ! [[ "$MY_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  echo "Unable to determine Jenkins public IPv4: '$MY_IP'" >&2
  exit 1
fi

ERR_FILE="$(mktemp)"
trap 'rm -f "$ERR_FILE"' EXIT
if ! STATUS="$(aws eks describe-cluster --name "$CLUSTER" --region "$REGION" --query cluster.status --output text 2>"$ERR_FILE")"; then
  if [[ "$ALLOW_MISSING_EKS" == "1" ]] && grep -q 'ResourceNotFoundException' "$ERR_FILE"; then
    echo "EKS $CLUSTER does not exist yet; Terraform can create it."
    exit 0
  fi
  cat "$ERR_FILE" >&2
  exit 1
fi

echo "EKS $CLUSTER status=$STATUS ; Jenkins public IP=$MY_IP"
case "$STATUS" in
  ACTIVE) ;;
  CREATING|UPDATING)
    echo "Waiting for EKS to become ACTIVE before changing API access..."
    aws eks wait cluster-active --name "$CLUSTER" --region "$REGION"
    ;;
  *) echo "EKS is $STATUS: fix this AWS state before deploying." >&2; exit 1 ;;
esac

PUBLIC=$(aws eks describe-cluster --name "$CLUSTER" --region "$REGION" \
   --query cluster.resourcesVpcConfig.endpointPublicAccess --output text)
if [[ "$PUBLIC" != "True" && "$PUBLIC" != "true" ]]; then
  echo 'Public EKS endpoint disabled: Jenkins must access through the VPC, VPN, or private network.' >&2
  exit 1
fi

CURRENT=$(aws eks describe-cluster --name "$CLUSTER" --region "$REGION" \
    --query "join(',',cluster.resourcesVpcConfig.publicAccessCidrs)" --output text)
if printf '%s\n' "$CURRENT" | tr ',' '\n' | grep -Fxq "$MY_IP/32"; then
  echo "EKS already authorizes $MY_IP/32; no EKS change required."
elif printf '%s\n' "$CURRENT" | tr ',' '\n' | grep -Fxq '0.0.0.0/0'; then
  echo 'EKS endpoint is already open to all IPv4 addresses. Tightening it is recommended.'
else
  # Preserve existing administrative CIDRs when adding the current Jenkins address.
  NEW_CIDRS="${CURRENT:+${CURRENT},}${MY_IP}/32"
  echo "Adding $MY_IP/32 to EKS public API allowlist (other entries preserved)."
  UPDATE_ID=$(aws eks update-cluster-config --name "$CLUSTER" --region "$REGION" \
    --resources-vpc-config "publicAccessCidrs=$NEW_CIDRS" \
    --query 'update.id' --output text)

  # Wait for the update itself: EKS status transitions can be eventually consistent.
  DONE=false
  for i in $(seq 1 90); do
    USTATUS=$(aws eks describe-update --name "$CLUSTER" --region "$REGION" \
       --update-id "$UPDATE_ID" --query 'update.status' --output text)
    case "$USTATUS" in
      Successful) DONE=true; break ;;
      Failed|Cancelled)
        aws eks describe-update --name "$CLUSTER" --region "$REGION" --update-id "$UPDATE_ID" \
          --query 'update.errors' --output json >&2
        exit 1 ;;
      *) sleep 10 ;;
    esac
  done
  if [[ "$DONE" != true ]]; then
    echo 'Timed out waiting for EKS API access update.' >&2
    exit 1
  fi
  aws eks wait cluster-active --name "$CLUSTER" --region "$REGION"
  echo "EKS public API now authorizes $MY_IP/32"
fi

# The Argo CD public NLB is also CIDR-restricted by Terraform's admin_cidr.
# Keep it in sync to avoid an Argo CD timeout after kubectl starts working.
# If Argo CD isn't installed yet (first infra apply), this is a no-op.
if command -v kubectl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" >/dev/null
  if kubectl -n argocd get svc argocd-server --request-timeout=15s -o json >/dev/null 2>&1; then
    SVC_JSON=$(kubectl -n argocd get svc argocd-server --request-timeout=15s -o json)
    SVC_TYPE=$(printf '%s' "$SVC_JSON" | jq -r '.spec.type')
    if [[ "$SVC_TYPE" == "LoadBalancer" ]]; then
      EXISTING_RANGES=$(printf '%s' "$SVC_JSON" | jq -r '.spec.loadBalancerSourceRanges[]?')
      if printf '%s\n' "$EXISTING_RANGES" | grep -Fxq "$MY_IP/32"; then
        echo "Argo CD LoadBalancer already authorizes $MY_IP/32."
      elif printf '%s\n' "$EXISTING_RANGES" | grep -Fxq '0.0.0.0/0'; then
        echo 'Argo CD LoadBalancer accepts any IPv4 address; review the security configuration.'
      elif [[ -z "$EXISTING_RANGES" ]]; then
        echo 'Argo CD LoadBalancer has no source CIDR restriction; leaving it unchanged.'
      else
        NEW_RANGES=$(printf '%s' "$SVC_JSON" | jq -c --arg ip "$MY_IP/32" \
          '(.spec.loadBalancerSourceRanges + [$ip]) | unique')
        echo "Updating Argo CD LoadBalancer to authorize $MY_IP/32."
        kubectl -n argocd patch svc argocd-server --type merge \
          -p "{\"spec\":{\"loadBalancerSourceRanges\":$NEW_RANGES}}"
        echo 'Argo CD network rules may take a short time to propagate.'
      fi
    fi
  else
    echo 'Argo CD Service not yet found or Kubernetes access unavailable; skipped LB update.'
  fi
fi
