#!/usr/bin/env bash
# =============================================================================
#  Étape 12 : décrire l'état voulu de l'environnement sur la branche GitOps.
#  Écrit envs/<env>/{config.json,values.yaml} sur GITOPS_BRANCH et enregistre :
#    gitops-revision.txt  commit de GITOPS_BRANCH contenant cet état (vérifié sur origin)
#    gitops-image.txt     image attendue dans l'Application Argo CD
#  Concurrence (autres builds, autres membres) : à chaque essai, les fichiers sont
#  régénérés sur le dernier état distant, sans rebase donc sans conflit possible.
#  Entrées : GIT_USER, GIT_TOKEN (credential github-credentials), PLATFORM_REPO,
#  GITOPS_BRANCH, ENV_NAME, K8S_NAMESPACE, HELM_PROFILE, OWNER, OWNER_SLUG,
#  FEATURE_SLUG, ECR_REGISTRY, APP_NAME, IMAGE_TAG, APP_HOST, BUILD_NUMBER, GIT_SHORT.
#  Le chart du commit construit est copié dans envs/<env>/chart : l'ApplicationSet lit chart
#  et valeurs à la même révision de GITOPS_BRANCH (exigé par Argo CD 2.13).
#  Réglage : GITOPS_PUSH_ATTEMPTS (5). GITOPS_REMOTE_URL remplace l'URL GitHub, CHART_SRC le
#  chart (platform/gitops/charts/events-app du workspace), pour les tests.
# =============================================================================
set -euo pipefail

ATTEMPTS="${GITOPS_PUSH_ATTEMPTS:-5}"
REMOTE="${GITOPS_REMOTE_URL:-https://github.com/${PLATFORM_REPO}.git}"
WORK="$(pwd)/gitops-work"
OUT="$(pwd)"
IMAGE="${ECR_REGISTRY}/${APP_NAME}:${IMAGE_TAG}"
CHART_SRC="${CHART_SRC:-$OUT/platform/gitops/charts/events-app}"
[[ -f "$CHART_SRC/Chart.yaml" ]] || { echo "Chart introuvable : $CHART_SRC/Chart.yaml" >&2; exit 1; }

rm -rf "$WORK" "$OUT/gitops-revision.txt" "$OUT/gitops-image.txt"
trap 'rm -rf "$WORK"' EXIT    # le jeton GitHub (config du clone) ne reste pas dans l'espace de travail

GIT_AUTH=()
if [[ -n "${GIT_TOKEN:-}" ]]; then
  GIT_AUTH=(-c "http.extraheader=AUTHORIZATION: basic $(printf '%s' "${GIT_USER}:${GIT_TOKEN}" | base64 | tr -d '\n')")
fi
git "${GIT_AUTH[@]}" clone --quiet --branch "$GITOPS_BRANCH" --depth 20 "$REMOTE" "$WORK"
cd "$WORK"
git config user.name  "Jenkins FST"
git config user.email "jenkins@fst-events.local"

write_env() {
  local dir="envs/$ENV_NAME"
  mkdir -p "$dir"
  cat > "$dir/config.json" <<EOF
{ "namespace": "$K8S_NAMESPACE", "profile": "$HELM_PROFILE", "owner": "$OWNER_SLUG" }
EOF
  cat > "$dir/values.yaml" <<EOF
# Généré par Jenkins — build #$BUILD_NUMBER — commit $GIT_SHORT — ne pas modifier à la main
feature: $FEATURE_SLUG
owner: $OWNER_SLUG
image:
  repository: $ECR_REGISTRY/$APP_NAME
  tag: $IMAGE_TAG
ingress:
  host: $APP_HOST
EOF
  rm -rf "$dir/chart"
  cp -R "$CHART_SRC" "$dir/chart"
  git add -A -- "$dir"
}

pushed=""
for attempt in $(seq 1 "$ATTEMPTS"); do
  if (( attempt > 1 )); then
    # Le clone de travail est jetable : on repart du dernier état distant
    git "${GIT_AUTH[@]}" fetch --quiet --depth 20 origin "$GITOPS_BRANCH"
    git reset --quiet --hard FETCH_HEAD
  fi
  write_env
  if git diff --cached --quiet; then
    echo "envs/$ENV_NAME est déjà à jour sur $GITOPS_BRANCH : aucun commit."
    pushed="$(git rev-parse HEAD)"
    break
  fi
  git commit --quiet -m "deploy($ENV_NAME): $IMAGE_TAG [build #$BUILD_NUMBER · $OWNER]"
  if git "${GIT_AUTH[@]}" push --quiet origin "HEAD:refs/heads/$GITOPS_BRANCH"; then
    pushed="$(git rev-parse HEAD)"
    break
  fi
  echo "Push refusé (essai $attempt/$ATTEMPTS) : $GITOPS_BRANCH a avancé, nouvel essai." >&2
  sleep $((attempt * 2))
done
[[ -n "$pushed" ]] || { echo "Échec du push GitOps après $ATTEMPTS essais." >&2; exit 1; }

# La révision enregistrée doit être sur la branche distante (rien de local ni d'écrasé)
git "${GIT_AUTH[@]}" fetch --quiet --depth 20 origin "$GITOPS_BRANCH"
if ! git merge-base --is-ancestor "$pushed" FETCH_HEAD; then
  echo "La révision $pushed n'est pas sur origin/$GITOPS_BRANCH après le push." >&2; exit 1
fi
printf '%s\n' "$pushed" > "$OUT/gitops-revision.txt"
printf '%s\n' "$IMAGE"  > "$OUT/gitops-image.txt"
printf 'Révision GitOps : %s (%s@%s), image %s\n' "$pushed" "$PLATFORM_REPO" "$GITOPS_BRANCH" "$IMAGE"
