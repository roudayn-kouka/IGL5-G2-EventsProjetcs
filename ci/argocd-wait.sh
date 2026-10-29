#!/usr/bin/env bash
# =============================================================================
#  Étape 13 : attendre qu'Argo CD ait appliqué LA révision GitOps poussée par ce
#  build (étape 12), avec l'image attendue, et que l'Application soit saine.
#
#  Application multi-source (ApplicationSet events-environments) :
#    source « chart »  : platform/gitops/charts/events-app sur main (évolue avec le code)
#    source « values » : envs/<env>/values.yaml sur GITOPS_BRANCH  <- révision comparée
#  .status.sync.revisions[i] suit l'ordre de .spec.sources : on compare la révision
#  de la source « values » au commit poussé, pas une révision quelconque.
#
#  Si un autre environnement est promu entre-temps, Argo CD peut appliquer un commit
#  plus récent : accepté seulement s'il descend du commit poussé et si envs/<env> n'a
#  pas changé (vérifié par git ; GIT_USER/GIT_TOKEN si le dépôt est privé).
#
#  Entrées : ARGOCD_SERVER, ARGOCD_AUTH_TOKEN (lus nativement par le CLI), ARGOCD_OPTS,
#  ENV_NAME, PLATFORM_REPO, GITOPS_BRANCH, fichiers gitops-revision.txt et gitops-image.txt.
#  Réglages : ARGOCD_WAIT_SECONDS (600), ARGOCD_POLL_SECONDS (10),
#  ARGOCD_APP_CREATE_SECONDS (180), ARGOCD_DEGRADED_GRACE_SECONDS (90),
#  ARGOCD_MAX_NETWORK_ERRORS (3).
# =============================================================================
set -euo pipefail
# shellcheck source=argocd-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/argocd-lib.sh"

WAIT="${ARGOCD_WAIT_SECONDS:-600}"
POLL="${ARGOCD_POLL_SECONDS:-10}"
CREATE_WAIT="${ARGOCD_APP_CREATE_SECONDS:-180}"
DEGRADED_GRACE="${ARGOCD_DEGRADED_GRACE_SECONDS:-90}"
MAX_NET_ERRORS="${ARGOCD_MAX_NETWORK_ERRORS:-3}"
APP="events-${ENV_NAME:?ENV_NAME manquant}"

[[ -n "${ARGOCD_SERVER:-}" ]] || { echo "ARGOCD_SERVER vide : make post-apply puis make configure." >&2; exit 1; }
[[ -n "${ARGOCD_AUTH_TOKEN:-}" ]] || { echo "Credential argocd-token vide." >&2; exit 1; }
[[ -s gitops-revision.txt ]] || { echo "gitops-revision.txt absent : l'étape 12 n'a pas enregistré la révision poussée." >&2; exit 1; }
[[ -s gitops-image.txt ]] || { echo "gitops-image.txt absent : l'étape 12 n'a pas enregistré l'image." >&2; exit 1; }
WANTED="$(tr -d '[:space:]' < gitops-revision.txt)"
IMAGE="$(tr -d '[:space:]' < gitops-image.txt)"
[[ "$WANTED" =~ ^[0-9a-f]{40}$ ]] || { echo "Révision GitOps invalide : « $WANTED »." >&2; exit 1; }
command -v argocd >/dev/null || { echo "CLI argocd absent de l'image Jenkins." >&2; exit 1; }

printf 'Attente de %s : révision %s (%s@%s), image %s, délai %ss.\n' \
  "$APP" "$WANTED" "$PLATFORM_REPO" "$GITOPS_BRANCH" "$IMAGE" "$WAIT"

# La révision déployée convient si c'est le commit poussé, ou un commit plus récent
# de GITOPS_BRANCH (autre environnement promu entre-temps) où envs/<env> est inchangé.
REV_REPO=""
values_rev_ok() {
  local rev="$1"
  [[ "$rev" == "$WANTED" ]] && return 0
  [[ "$rev" =~ ^[0-9a-f]{40}$ ]] || return 1
  if [[ -z "$REV_REPO" ]]; then
    REV_REPO="$(mktemp -d)"
    git init --quiet --bare "$REV_REPO"
  fi
  local auth=()
  [[ -n "${GIT_TOKEN:-}" ]] && auth=(-c "http.extraheader=AUTHORIZATION: basic $(printf '%s' "${GIT_USER}:${GIT_TOKEN}" | base64 | tr -d '\n')")
  if ! git -C "$REV_REPO" cat-file -e "${rev}^{commit}" 2>/dev/null; then
    git -C "$REV_REPO" "${auth[@]}" fetch --quiet --depth 100 "${GITOPS_REMOTE_URL:-https://github.com/${PLATFORM_REPO}.git}" \
      "+refs/heads/${GITOPS_BRANCH}:refs/heads/${GITOPS_BRANCH}" || return 1
  fi
  git -C "$REV_REPO" merge-base --is-ancestor "$WANTED" "$rev" 2>/dev/null || return 1
  if ! git -C "$REV_REPO" diff --quiet "$WANTED" "$rev" -- "envs/$ENV_NAME"; then
    echo "envs/$ENV_NAME a été modifié après $WANTED (promotion plus récente) : ce déploiement est remplacé." >&2
    exit 1
  fi
  return 0
}

diagnose() {
  local json="$1"
  echo "--- Diagnostic $APP ---" >&2
  jq -r '"opération : \(.status.operationState.phase // "aucune") — \(.status.operationState.message // "")",
         "conditions : \([(.status.conditions // [])[] | "\(.type): \(.message)"] | join(" | "))",
         "images : \((.status.summary.images // []) | join(", "))",
         (.status.resources // [] | map(select((.health.status // "Healthy") != "Healthy" or .status != "Synced"))
           | .[] | "ressource \(.kind)/\(.name) : sync=\(.status) santé=\(.health.status // "-") \(.health.message // "")")' \
    <<<"$json" >&2 || true
}

start=$SECONDS
deadline=$((SECONDS + WAIT))
net_errors=0
degraded_since=""
checked_source=false
json=""
err_file="$(mktemp)"
trap 'rm -rf "$err_file" "$REV_REPO"' EXIT

while (( SECONDS < deadline )); do
  if ! json="$(argocd app get "$APP" --refresh -o json 2>"$err_file")"; then
    err="$(cat "$err_file")"
    if argocd_explain "$err"; then           # erreur transitoire
      case "$err" in
        *"NotFound"*|*"not found"*)
          if (( SECONDS - start > CREATE_WAIT )); then
            echo "Application $APP toujours absente après ${CREATE_WAIT}s : vérifier envs/$ENV_NAME/config.json sur $GITOPS_BRANCH et l'ApplicationSet." >&2
            exit 1
          fi ;;
        *)
          net_errors=$((net_errors + 1))
          if (( net_errors >= MAX_NET_ERRORS )); then
            echo "Abandon après $net_errors erreurs réseau consécutives." >&2; exit 1
          fi ;;
      esac
      sleep "$POLL"; continue
    fi
    exit 1                                    # configuration, DNS, TLS, authentification, droits
  fi
  net_errors=0

  if ! jq -e '.metadata.name and .status' >/dev/null 2>&1 <<<"$json"; then
    printf 'Réponse Argo CD invalide (JSON attendu) : %s\n' "$(head -c 300 <<<"$json")" >&2
    exit 1
  fi
  if [[ "$checked_source" == false ]]; then
    argocd_check_values_source "$json" "$APP" || exit 1
    checked_source=true
  fi

  idx="$(argocd_values_index "$json")"
  rev="$(jq -r --argjson i "$idx" '.status.sync.revisions[$i] // ""' <<<"$json")"
  chart_rev="$(jq -r --argjson i "$idx" '[(.status.sync.revisions // []) | to_entries[] | select(.key != $i) | .value] | join(",")' <<<"$json")"
  sync="$(jq -r '.status.sync.status // "?"' <<<"$json")"
  health="$(jq -r '.status.health.status // "?"' <<<"$json")"
  phase="$(jq -r '.status.operationState.phase // "-"' <<<"$json")"
  has_image="$(jq -r --arg img "$IMAGE" '(.status.summary.images // []) | index($img) != null' <<<"$json")"

  printf '[%3ss] %s valeurs=%s chart=%s sync=%s santé=%s opération=%s image-attendue=%s\n' \
    "$((SECONDS - start))" "$APP" "${rev:0:7}" "${chart_rev:0:7}" "$sync" "$health" "$phase" "$has_image"

  if values_rev_ok "$rev"; then
    if [[ "$phase" == "Failed" || "$phase" == "Error" ]]; then
      echo "Synchronisation de la révision $WANTED en échec." >&2; diagnose "$json"; exit 1
    fi
    if [[ "$sync" == "Synced" && "$health" == "Healthy" ]]; then
      if [[ "$has_image" != "true" ]]; then
        echo "Révision appliquée et saine, mais l'image $IMAGE n'est pas déployée." >&2; diagnose "$json"; exit 1
      fi
      printf 'Déployé et sain : %s @ %s, image %s (%ss).\n' "$APP" "$WANTED" "$IMAGE" "$((SECONDS - start))"
      exit 0
    fi
    if [[ "$health" == "Degraded" ]]; then
      degraded_since="${degraded_since:-$SECONDS}"
      if (( SECONDS - degraded_since >= DEGRADED_GRACE )); then
        echo "Application dégradée depuis ${DEGRADED_GRACE}s avec la révision attendue." >&2; diagnose "$json"; exit 1
      fi
    else
      degraded_since=""
    fi
  fi
  sleep "$POLL"
done

echo "Délai de ${WAIT}s dépassé : $APP n'a pas atteint révision $WANTED + Synced + Healthy." >&2
[[ -n "$json" ]] && diagnose "$json"
exit 1
