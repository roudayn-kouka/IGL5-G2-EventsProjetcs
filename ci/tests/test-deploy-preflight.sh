#!/usr/bin/env bash
# =============================================================================
#  Tests de ci/deploy-preflight.sh avec de faux CLI argocd/aws (aucun accès réel).
#  Usage : bash ci/tests/test-deploy-preflight.sh   (requiert bash, jq)
# =============================================================================
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI="$(cd "$HERE/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
mkdir -p "$T/bin"
for t in git curl docker; do printf '#!/bin/sh\nexit 0\n' > "$T/bin/$t"; done
cat > "$T/bin/aws" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "sts get-caller-identity") echo "arn:aws:sts::315488743028:assumed-role/LabRole/i-0123" ;;
  "ecr describe-repositories") [ "${FAKE_ECR:-ok}" = ok ] && echo uri || { echo "RepositoryNotFoundException" >&2; exit 254; } ;;
esac
EOF
cat > "$T/bin/argocd" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "version --client") echo "argocd: v2.13.3+fake" ;;
  "account get-user-info") [ "${FAKE_AUTH:-ok}" = ok ] && echo '{"loggedIn":true,"username":"jenkins"}' \
       || { echo "rpc error: code = Unauthenticated desc = invalid session" >&2; exit 20; } ;;
  "app get")
    case "${FAKE_APP_GET:-ok}" in
      denied)   echo "rpc error: code = PermissionDenied desc = permission denied: projects, get, events, sub: jenkins" >&2; exit 20 ;;
      notfound) echo "rpc error: code = NotFound desc = applications.argoproj.io \"$3\" not found" >&2; exit 20 ;;
      *) jq --arg b "${FAKE_VALUES_BRANCH:-gitops}" --arg c "${FAKE_CHART_BRANCH:-gitops}" \
           '.spec.sources[1].targetRevision = $b | .spec.sources[0].targetRevision = $c' "$FIXTURE" ;;
    esac ;;
esac
EOF
chmod +x "$T/bin/"*

run() {   # run <nom> <code attendu> <motif> <VAR=valeur…>
  local name="$1" want="$2" pattern="$3"; shift 3
  out="$(env -i PATH="$T/bin:$PATH" HOME="$T" TMPDIR="$T" FIXTURE="$HERE/fixtures/app-multisource.json" \
        ENV_NAME=staging K8S_NAMESPACE=events-staging HELM_PROFILE=staging APP_NAME=events-app \
        ECR_REGISTRY=315488743028.dkr.ecr.us-east-1.amazonaws.com AWS_REGION=us-east-1 \
        PLATFORM_REPO=roudayn-kouka/IGL5-G2-EventsProjetcs GITOPS_BRANCH=gitops \
        APPS_DOMAIN=32.196.158.224.sslip.io ARGOCD_SERVER=argocd.internal:80 ARGOCD_AUTH_TOKEN=x \
        "$@" bash "$CI/deploy-preflight.sh" 2>&1)"; code=$?
  if [[ "$code" == "$want" ]] && grep -q -- "$pattern" <<<"$out"; then
    pass=$((pass + 1)); printf 'OK    %s\n' "$name"
  else
    fail=$((fail + 1)); printf 'ÉCHEC %s (code %s, attendu %s)\n%s\n' "$name" "$code" "$want" "$out" | sed 's/^/      /'
  fi
}

run "configuration complète"                    0 "Prérequis de déploiement vérifiés"
run "état réel du build #7 (3 valeurs vides)"   1 "3 prérequis manquant" ARGOCD_SERVER= APPS_DOMAIN= ARGOCD_AUTH_TOKEN=
run "GITOPS_BRANCH = main (boucle de builds)"   1 "branche construite par Jenkins" GITOPS_BRANCH=main
run "APPS_DOMAIN non résolvable"                1 "n'est pas résolvable" APPS_DOMAIN=apps.local
run "registre ECR d'une autre région"           1 "n'est pas dans AWS_REGION" AWS_REGION=eu-west-3
run "ARGOCD_SERVER avec schéma"                 1 "sans schéma" ARGOCD_SERVER=http://argocd:80
run "namespace incohérent"                      1 "Namespace" K8S_NAMESPACE=events-prod
run "dépôt ECR absent"                          1 "Dépôt ECR events-app inaccessible" FAKE_ECR=absent
run "jeton Argo CD refusé"                      1 "erreur AUTHENTIFICATION" FAKE_AUTH=refuse
run "Argo CD lit les valeurs sur main"          1 "lit les valeurs sur .*@main" FAKE_VALUES_BRANCH=main
run "chart sur main, valeurs sur gitops (2.13)"   1 "refuse deux révisions du même dépôt" FAKE_CHART_BRANCH=main
run "lecture Application refusée (RBAC)"         1 "erreur AUTORISATION" FAKE_APP_GET=denied
run "Application absente : toléré"              0 "Prérequis de déploiement vérifiés" FAKE_APP_GET=notfound

printf '\n%s réussi(s), %s échoué(s)\n' "$pass" "$fail"
(( fail == 0 ))
