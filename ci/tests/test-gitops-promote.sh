#!/usr/bin/env bash
# =============================================================================
#  Tests de ci/gitops-promote.sh contre un dépôt Git local (aucun accès GitHub).
#  Usage : bash ci/tests/test-gitops-promote.sh   (requiert bash, git)
# =============================================================================
set -uo pipefail
CI="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass + 1)); printf 'OK    %s\n' "$1"; }
ko()  { fail=$((fail + 1)); printf 'ÉCHEC %s\n%s\n' "$1" "${2:-}" | sed '2,$s/^/      /'; }

git init --quiet --bare "$T/remote.git"
git clone --quiet "$T/remote.git" "$T/seed" 2>/dev/null
( cd "$T/seed" && git config user.email t@t && git config user.name t && git checkout --quiet -b gitops
  mkdir -p envs/prod && echo "tag: prod-1" > envs/prod/values.yaml && git add -A && git commit --quiet -m init
  git push --quiet origin gitops )

# Chart du build (copié dans envs/<env>/chart par la promotion)
mkdir -p "$T/chart/templates"
printf 'apiVersion: v2\nname: events-app\nversion: 1.0.0\n' > "$T/chart/Chart.yaml"
echo "kind: Deployment" > "$T/chart/templates/deployment.yaml"
echo "obsolete" > "$T/chart/templates/obsolete.yaml"

promote() {   # promote <tag> -> exécute le script dans $T/job
  rm -rf "$T/job"; mkdir -p "$T/job"
  (cd "$T/job" && GITOPS_REMOTE_URL="file://$T/remote.git" PLATFORM_REPO=o/r GITOPS_BRANCH=gitops \
     ENV_NAME=staging K8S_NAMESPACE=events-staging HELM_PROFILE=staging OWNER="Equipe" OWNER_SLUG=equipe \
     FEATURE_SLUG=staging ECR_REGISTRY=315488743028.dkr.ecr.us-east-1.amazonaws.com APP_NAME=events-app \
     IMAGE_TAG="$1" APP_HOST=staging.1.2.3.4.sslip.io BUILD_NUMBER=8 GIT_SHORT=abc1234 \
     GITOPS_PUSH_ATTEMPTS="${ATTEMPTS:-5}" CHART_SRC="${CHART_SRC:-$T/chart}" bash "$CI/gitops-promote.sh" 2>&1)
}
remote_head() { git --git-dir="$T/remote.git" rev-parse refs/heads/gitops; }

# 1. Première promotion : fichiers écrits, révision = tête distante, image enregistrée
out="$(promote staging-8-abc1234)"; rc=$?
if (( rc == 0 )) && [[ "$(cat "$T/job/gitops-revision.txt")" == "$(remote_head)" ]] \
   && grep -q "tag: staging-8-abc1234" <(git --git-dir="$T/remote.git" show gitops:envs/staging/values.yaml) \
   && grep -q '"profile": "staging"' <(git --git-dir="$T/remote.git" show gitops:envs/staging/config.json) \
   && [[ "$(cat "$T/job/gitops-image.txt")" == "315488743028.dkr.ecr.us-east-1.amazonaws.com/events-app:staging-8-abc1234" ]] \
   && grep -q "tag: prod-1" <(git --git-dir="$T/remote.git" show gitops:envs/prod/values.yaml) \
   && [[ ! -d "$T/job/gitops-work" ]]; then
  ok "promotion : commit poussé, révision et image enregistrées, prod intacte, clone supprimé"
else ko "promotion" "$out"; fi

# 1b. Chart du build copié dans envs/staging/chart ; un fichier retiré du chart disparaît
if git --git-dir="$T/remote.git" show gitops:envs/staging/chart/Chart.yaml | grep -q 'name: events-app'; then
  ok "promotion : chart du build copié dans envs/staging/chart"; else ko "chart non copié"; fi
rm "$T/chart/templates/obsolete.yaml"
out="$(promote staging-8-abc1234)"
if ! git --git-dir="$T/remote.git" cat-file -e gitops:envs/staging/chart/templates/obsolete.yaml 2>/dev/null \
   && ! git --git-dir="$T/remote.git" cat-file -e gitops:envs/prod/chart 2>/dev/null; then
  ok "promotion : chart remplacé (fichier supprimé retiré), autres environnements intacts"
else ko "remplacement du chart" "$out"; fi
out="$(CHART_SRC="$T/absent" promote staging-8-abc1234)"; rc=$?
(( rc != 0 )) && grep -q "Chart introuvable" <<<"$out" && ok "chart absent : échec explicite" || ko "chart absent" "$out"

# 2. Même état : aucun commit vide, révision = tête distante
before="$(remote_head)"; out="$(promote staging-8-abc1234)"; rc=$?
if (( rc == 0 )) && [[ "$(remote_head)" == "$before" ]] && grep -q "aucun commit" <<<"$out" \
   && [[ "$(cat "$T/job/gitops-revision.txt")" == "$before" ]]; then
  ok "aucun changement : pas de commit vide"
else ko "aucun changement" "$out"; fi

# 3. Push refusé une fois (promotion concurrente) : régénération puis succès
cat > "$T/remote.git/hooks/pre-receive" <<EOF
#!/bin/sh
[ -f "$T/rejected" ] && exit 0
touch "$T/rejected"; echo "refus simulé (branche avancée)" >&2; exit 1
EOF
chmod +x "$T/remote.git/hooks/pre-receive"
out="$(promote staging-9-def5678)"; rc=$?
if (( rc == 0 )) && grep -q "essai 1/5" <<<"$out" && [[ "$(cat "$T/job/gitops-revision.txt")" == "$(remote_head)" ]] \
   && grep -q "tag: staging-9-def5678" <(git --git-dir="$T/remote.git" show gitops:envs/staging/values.yaml); then
  ok "push concurrent : nouvel essai réussi, révision finale enregistrée"
else ko "push concurrent" "$out"; fi

# 4. Push toujours refusé : échec explicite, aucune révision enregistrée
printf '#!/bin/sh\necho "refus permanent" >&2\nexit 1\n' > "$T/remote.git/hooks/pre-receive"
out="$(ATTEMPTS=2 promote staging-10-0000000)"; rc=$?
if (( rc != 0 )) && grep -q "Échec du push GitOps après 2 essais" <<<"$out" && [[ ! -e "$T/job/gitops-revision.txt" ]]; then
  ok "push impossible : échec explicite, pas de révision enregistrée"
else ko "push impossible" "$out"; fi

printf '\n%s réussi(s), %s échoué(s)\n' "$pass" "$fail"
(( fail == 0 ))
