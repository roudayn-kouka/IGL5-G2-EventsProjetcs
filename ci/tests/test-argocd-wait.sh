#!/usr/bin/env bash
# =============================================================================
#  Tests de ci/argocd-wait.sh sans cluster : un faux CLI « argocd » rejoue des
#  réponses (JSON d'Application réel ou erreurs) à chaque appel.
#  Usage : bash ci/tests/test-argocd-wait.sh   (requiert bash, jq, git)
# =============================================================================
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI="$(cd "$HERE/.." && pwd)"
FIXTURE="$HERE/fixtures/app-multisource.json"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0

# --- Dépôt GitOps local : C1 (commit poussé), C2 (autre env), C3 (même env modifié) ---
git init --quiet --bare "$T/remote.git"
git clone --quiet "$T/remote.git" "$T/w" 2>/dev/null
( cd "$T/w" && git config user.email t@t && git config user.name t && git checkout --quiet -b gitops
  mkdir -p envs/staging envs/other
  echo v1 > envs/staging/values.yaml && git add -A && git commit --quiet -m c1
  echo o1 > envs/other/values.yaml   && git add -A && git commit --quiet -m c2
  echo v2 > envs/staging/values.yaml && git add -A && git commit --quiet -m c3
  git push --quiet origin gitops )
C1="$(git -C "$T/w" rev-parse HEAD~2)"; C2="$(git -C "$T/w" rev-parse HEAD~1)"; C3="$(git -C "$T/w" rev-parse HEAD)"
IMAGE="315488743028.dkr.ecr.us-east-1.amazonaws.com/events-app:staging-8-abc1234"

# --- Faux CLI : chaque appel consomme la ligne suivante de $T/script ---------------
mkdir -p "$T/bin"
cat > "$T/bin/argocd" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == "version" ]] && { echo "argocd: v2.13.3+fake"; exit 0; }
n=$(cat "$FAKE_DIR/n" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$FAKE_DIR/n"
line="$(sed -n "${n}p" "$FAKE_DIR/script")"; [[ -z "$line" ]] && line="$(tail -1 "$FAKE_DIR/script")"
case "$line" in
  err:*) echo "${line#err:}" >&2; exit 20 ;;
  raw:*) echo "${line#raw:}"; exit 0 ;;
  *)     cat "$FAKE_DIR/$line"; exit 0 ;;
esac
EOF
chmod +x "$T/bin/argocd"

# app <fichier> <révision values> <sync> <santé> <image> [branche values] [phase]
app() {
  jq --arg rev "$2" --arg sync "$3" --arg health "$4" --arg img "$5" --arg br "${6:-gitops}" --arg ph "${7:-Succeeded}" '
    .spec.sources[1].targetRevision = $br
    | .status.sync.revisions = ["chartsha0000000000000000000000000000000000", $rev]
    | .status.sync.status = $sync | .status.health.status = $health
    | .status.summary.images = [$img, "mysql:8.0"]
    | .status.operationState.phase = $ph' "$FIXTURE" > "$T/$1"
}

run() {   # run <nom> <code attendu> <motif attendu dans la sortie> <lignes du script…>
  local name="$1" want="$2" pattern="$3"; shift 3
  rm -f "$T/n"; printf '%s\n' "$@" > "$T/script"
  printf '%s\n' "$C1" > "$T/gitops-revision.txt"; printf '%s\n' "$IMAGE" > "$T/gitops-image.txt"
  out="$(cd "$T" && PATH="$T/bin:$PATH" FAKE_DIR="$T" ENV_NAME=staging PLATFORM_REPO=roudayn-kouka/IGL5-G2-EventsProjetcs \
        GITOPS_BRANCH=gitops ARGOCD_SERVER=argocd.test:80 ARGOCD_AUTH_TOKEN=x GITOPS_REMOTE_URL="file://$T/remote.git" \
        ARGOCD_POLL_SECONDS=0 ARGOCD_WAIT_SECONDS=5 ARGOCD_APP_CREATE_SECONDS=2 ARGOCD_DEGRADED_GRACE_SECONDS=0 \
        bash "$CI/argocd-wait.sh" 2>&1)"; code=$?
  if [[ "$code" == "$want" ]] && grep -q -- "$pattern" <<<"$out"; then
    pass=$((pass + 1)); printf 'OK    %s\n' "$name"
  else
    fail=$((fail + 1)); printf 'ÉCHEC %s (code %s, attendu %s)\n%s\n' "$name" "$code" "$want" "$out" | sed 's/^/      /'
  fi
}

app ok.json       "$C1" Synced Healthy "$IMAGE"
app old.json      "0000000000000000000000000000000000000000" Synced Healthy "previous:image"
app prog.json     "$C1" OutOfSync Progressing "$IMAGE"
app degr.json     "$C1" Synced Degraded "$IMAGE"
app wrongimg.json "$C1" Synced Healthy "other:image"
app main.json     "$C1" Synced Healthy "$IMAGE" main
app newer.json    "$C2" Synced Healthy "$IMAGE"
app super.json    "$C3" Synced Healthy "$IMAGE"
app failed.json   "$C1" OutOfSync Progressing "$IMAGE" gitops Failed

run "serveur non défini (cause du build #7)" 1 "erreur CONFIGURATION" "err:time=x level=fatal msg=\"Argo CD server address unspecified\""
run "jeton invalide"                         1 "erreur AUTHENTIFICATION" "err:rpc error: code = Unauthenticated desc = invalid session"
run "droits insuffisants"                    1 "erreur AUTORISATION" "err:rpc error: code = PermissionDenied desc = permission denied"
run "DNS"                                    1 "erreur DNS" "err:dial tcp: lookup argocd.test: no such host"
run "TLS"                                    1 "erreur TLS" "err:x509: certificate signed by unknown authority"
run "réseau : 3 erreurs puis abandon"        1 "Abandon après 3 erreurs" "err:dial tcp 10.0.0.1:80: i/o timeout"
run "réseau transitoire puis succès"         0 "Déployé et sain" "err:connection refused" ok.json
run "réponse non JSON"                       1 "Réponse Argo CD invalide" "raw:<html>proxy</html>"
run "valeurs lues sur main (commit 499f28b)" 1 "lit les valeurs sur .*@main" main.json
run "ancienne révision puis la bonne"        0 "Déployé et sain" old.json prog.json ok.json
run "application créée par l'ApplicationSet" 0 "Déployé et sain" "err:rpc error: code = NotFound desc = applications.argoproj.io \"events-staging\" not found" ok.json
run "application jamais créée"               1 "toujours absente" "err:rpc error: code = NotFound desc = not found"
run "révision appliquée mais dégradée"       1 "dégradée" degr.json
run "synchronisation en échec"               1 "en échec" failed.json
run "révision saine mais mauvaise image"     1 "n'est pas déployée" wrongimg.json
run "commit plus récent, env inchangé"       0 "Déployé et sain" newer.json
run "commit plus récent, env modifié"        1 "remplacé" super.json
run "délai dépassé"                          1 "Délai de 5s dépassé" old.json

printf '\n%s réussi(s), %s échoué(s)\n' "$pass" "$fail"
(( fail == 0 ))
