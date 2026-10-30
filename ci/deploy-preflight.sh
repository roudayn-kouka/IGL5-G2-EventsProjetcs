#!/usr/bin/env bash
# =============================================================================
#  Prérequis du déploiement, vérifiés AVANT le build (étape 1) : un paramètre
#  manquant échoue en quelques secondes au lieu de bloquer l'étape 13.
#  Entrées (environnement Jenkins) : ENV_NAME, K8S_NAMESPACE, HELM_PROFILE,
#  APP_NAME, ECR_REGISTRY, AWS_REGION, PLATFORM_REPO, GITOPS_BRANCH,
#  APPS_DOMAIN, ARGOCD_SERVER, ARGOCD_AUTH_TOKEN (credential argocd-token).
#  Aucun secret n'est affiché.
# =============================================================================
set -euo pipefail

errors=0
fail() { printf 'PRÉREQUIS MANQUANT : %s\n' "$*" >&2; errors=$((errors + 1)); }
need() { [[ -n "${!1:-}" ]] || fail "$1 est vide. $2"; }

# --- Paramètres (variables globales Jenkins, injectées par Ansible/JCasC) ----------
need ECR_REGISTRY   "Variable globale Jenkins (JCasC, ecr_registry)."
need AWS_REGION     "Variable globale Jenkins (JCasC, aws_region)."
need PLATFORM_REPO  "Variable globale Jenkins (JCasC, platform_repo), ex. owner/depot."
need GITOPS_BRANCH  "Variable globale Jenkins (JCasC, gitops_branch), ex. gitops."
need APPS_DOMAIN    "Écrite par « make post-apply » dans runtime.yml puis « make configure » (ex. 1.2.3.4.sslip.io)."
need ARGOCD_SERVER  "Écrite par « make post-apply » dans runtime.yml puis « make configure » (DNS du NLB interne argocd-server:80)."
need ARGOCD_AUTH_TOKEN "Credential Jenkins « argocd-token » vide : générer le jeton du compte jenkins (make argocd-token) puis vault_argocd_token et « make configure »."

if [[ -n "${ECR_REGISTRY:-}" && ! "$ECR_REGISTRY" =~ ^[0-9]{12}\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com$ ]]; then
  fail "ECR_REGISTRY « $ECR_REGISTRY » n'est pas un registre ECR (<compte>.dkr.ecr.<région>.amazonaws.com)."
fi
if [[ -n "${ECR_REGISTRY:-}" && -n "${AWS_REGION:-}" && "$ECR_REGISTRY" != *".dkr.ecr.${AWS_REGION}."* ]]; then
  fail "ECR_REGISTRY ($ECR_REGISTRY) n'est pas dans AWS_REGION ($AWS_REGION)."
fi
if [[ -n "${PLATFORM_REPO:-}" && ! "$PLATFORM_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  fail "PLATFORM_REPO « $PLATFORM_REPO » doit être de la forme owner/depot."
fi
# Anti-boucle : la branche GitOps ne doit jamais être une branche construite par Jenkins
if [[ "${GITOPS_BRANCH:-}" =~ ^(main|develop|release/.*|hotfix/.*|feature/.*)$ ]]; then
  fail "GITOPS_BRANCH « $GITOPS_BRANCH » est une branche construite par Jenkins : chaque promotion relancerait un build."
fi
if [[ "${APPS_DOMAIN:-}" == *.local || "${APPS_DOMAIN:-}" == *"<"* ]]; then
  fail "APPS_DOMAIN « $APPS_DOMAIN » n'est pas résolvable (attendu <IP du NLB ingress>.sslip.io)."
fi
if [[ -n "${ARGOCD_SERVER:-}" && "$ARGOCD_SERVER" =~ ^https?:// ]]; then
  fail "ARGOCD_SERVER doit être hôte[:port] sans schéma (reçu « $ARGOCD_SERVER »)."
fi

# --- Cohérence du contexte calculé à l'étape 1 -----------------------------------
[[ "${K8S_NAMESPACE:-}" == "events-${ENV_NAME:-}" ]] || fail "Namespace « ${K8S_NAMESPACE:-} » ≠ events-${ENV_NAME:-}."
[[ "${HELM_PROFILE:-}" =~ ^(review|staging|prod)$ ]] || fail "Profil Helm « ${HELM_PROFILE:-} » inconnu (review, staging, prod)."
[[ "${ENV_NAME:-}" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || fail "Nom d'environnement « ${ENV_NAME:-} » invalide pour Kubernetes."

if (( errors > 0 )); then
  printf '%s prérequis manquant(s) : déploiement impossible. Voir docs/GUIDE-EXECUTION.md, « Build en un clic ».\n' "$errors" >&2
  exit 1
fi

# --- Outils -------------------------------------------------------------------------
for tool in argocd jq aws git curl docker; do
  command -v "$tool" >/dev/null || { printf 'Outil absent de l image Jenkins : %s\n' "$tool" >&2; exit 1; }
done
printf 'CLI Argo CD : %s\n' "$(argocd version --client --short 2>&1 | head -1)"

# --- AWS : identité et dépôt ECR (rôle de l'instance, aucune clé stockée) ------------
if ! identity="$(aws sts get-caller-identity --query Arn --output text 2>&1)"; then
  printf 'AWS inaccessible depuis Jenkins (rôle de l instance ?) : %s\n' "$identity" >&2; exit 1
fi
printf 'Identité AWS : %s\n' "$identity"
if ! aws ecr describe-repositories --region "$AWS_REGION" --repository-names "$APP_NAME" \
     --query 'repositories[0].repositoryUri' --output text >/dev/null 2>"${TMPDIR:-/tmp}/ecr.err"; then
  printf 'Dépôt ECR %s inaccessible dans %s : %s\n' "$APP_NAME" "$AWS_REGION" "$(head -c 300 "${TMPDIR:-/tmp}/ecr.err")" >&2; exit 1
fi
printf 'Dépôt ECR : %s/%s\n' "$ECR_REGISTRY" "$APP_NAME"

# --- Argo CD : réseau, TLS, authentification (le CLI lit ARGOCD_SERVER et ARGOCD_AUTH_TOKEN) ---
# shellcheck source=argocd-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/argocd-lib.sh"
if ! user_info="$(argocd account get-user-info -o json 2>"${TMPDIR:-/tmp}/argocd.err")"; then
  argocd_explain "$(cat "${TMPDIR:-/tmp}/argocd.err")"; exit 1
fi
if ! jq -e '.loggedIn == true' >/dev/null <<<"$user_info"; then
  echo "Argo CD : jeton refusé (loggedIn=false). Régénérer le jeton du compte jenkins." >&2; exit 1
fi
printf 'Argo CD : connecté en tant que %s sur %s\n' "$(jq -r '.username' <<<"$user_info")" "$ARGOCD_SERVER"

# --- Argo CD lit-il bien la branche où Jenkins va pousser ? --------------------------
# (Une Application existante suffit : toutes viennent du même ApplicationSet.)
# Seule l'absence de l'Application est tolérée (nouvel environnement) ; un refus de droits
# ou une erreur réseau ferait échouer l'étape 13 : on l'arrête ici, explicitement.
for app in "events-$ENV_NAME" events-staging; do
  if app_json="$(argocd app get "$app" -o json 2>"${TMPDIR:-/tmp}/argocd-app.err")"; then
    argocd_check_values_source "$app_json" "$app" || exit 1
    break
  fi
  app_err="$(cat "${TMPDIR:-/tmp}/argocd-app.err")"
  case "$app_err" in
    *"NotFound"*|*"not found"*) continue ;;
    *) argocd_explain "$app_err"; exit 1 ;;
  esac
done
echo "Prérequis de déploiement vérifiés."
