#!/usr/bin/env bash
set -euo pipefail

# shellcheck source-path=SCRIPTDIR source=region.sh
source "$(dirname "${BASH_SOURCE[0]}")/region.sh"
REGION="$(resolve_region)"
PREFIX="${TF_STATE_BUCKET_PREFIX:-fst-events-tfstate}"
TABLE="${TF_STATE_LOCK_TABLE:-fst-events-tflock}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="${TF_STATE_BUCKET:-${PREFIX}-${ACCOUNT_ID}-${REGION}}"

if [[ ! "$BUCKET" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]]; then
  printf 'Nom de bucket S3 invalide : %s\n' "$BUCKET" >&2
  exit 1
fi

if ! aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
  if [[ "$REGION" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"
  else
    aws s3api create-bucket \
      --bucket "$BUCKET" \
      --region "$REGION" \
      --create-bucket-configuration "LocationConstraint=$REGION"
  fi
fi

aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

if ! aws dynamodb describe-table --table-name "$TABLE" --region "$REGION" >/dev/null 2>&1; then
  aws dynamodb create-table \
    --table-name "$TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION"
  aws dynamodb wait table-exists --table-name "$TABLE" --region "$REGION"
fi

printf 'Backend initialisé.\nBucket : %s\nTable de verrou : %s\nCopiez terraform/backend.hcl.example vers terraform/backend.hcl et renseignez ce bucket.\n' "$BUCKET" "$TABLE"
