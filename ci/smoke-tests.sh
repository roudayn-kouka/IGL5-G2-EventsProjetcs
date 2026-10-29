#!/usr/bin/env bash
# =============================================================================
#  Étape 14a : tests post-déploiement sur l'URL réelle de l'environnement.
#  APP_HOST = <env>.<APPS_DOMAIN> (sslip.io résout vers le NLB ingress, l'ingress
#  route sur l'hôte HTTP : un mauvais environnement répond 404).
#  Chaque requête vérifie le code HTTP exact ; les redirections ne sont pas suivies.
#  Entrées : APP_HOST, BRANCH_TYPE. Réglages : SMOKE_WAIT_SECONDS (180),
#  SMOKE_BASE_URL (remplace http://APP_HOST, pour les tests locaux).
# =============================================================================
set -euo pipefail

BASE="${SMOKE_BASE_URL:-http://${APP_HOST:?APP_HOST manquant}}/events"
WAIT="${SMOKE_WAIT_SECONDS:-180}"
STRICT_API=false
[[ "${BRANCH_TYPE:-}" =~ ^(develop|release|hotfix|main)$ ]] && STRICT_API=true
body="$(mktemp)"; trap 'rm -f "$body"' EXIT
failures=0

curl_error() {
  case "$1" in
    6)  echo "DNS : le nom de $BASE ne se résout pas (APPS_DOMAIN ?)";;
    7)  echo "connexion refusée (NLB ingress ou pods indisponibles)";;
    28) echo "délai dépassé";;
    35|60) echo "erreur TLS";;
    *)  echo "erreur curl $1";;
  esac
}

# get <chemin> -> code HTTP dans $code, en-têtes Location/Content-Type, corps dans $body
get() {
  local out rc
  set +e
  out="$(curl -sS --max-time 15 -o "$body" -w '%{http_code} %{content_type} %{redirect_url}' "$BASE$1" 2>&1)"
  rc=$?
  set -e
  if (( rc != 0 )); then code="000"; detail="$(curl_error "$rc")"; return 1; fi
  read -r code ctype location <<<"$out"
  detail=""
}

content_ok() {   # contrôle du corps selon le type attendu
  case "$1" in
    html)    [[ "$ctype" == text/html* ]] && grep -qi "<html" "$body" ;;
    json)    [[ "$ctype" == application/json* ]] && jq -e 'type == "object" or type == "array"' "$body" >/dev/null ;;
    up)      jq -e '.status == "UP"' "$body" >/dev/null ;;
    metrics) grep -q "^jvm_" "$body" ;;
    *)       return 0 ;;
  esac
}

check() {   # check <chemin> <code attendu> <description> [html|json|up|metrics]
  local path="$1" want="$2" what="$3" kind="${4:-}"
  get "$path" || { echo "ÉCHEC $what ($path) : $detail"; failures=$((failures + 1)); return; }
  if [[ "$code" =~ ^3 ]]; then
    echo "ÉCHEC $what ($path) : redirection HTTP $code vers ${location:-?} (non suivie)"; failures=$((failures + 1)); return
  fi
  if [[ "$code" != "$want" ]]; then
    echo "ÉCHEC $what ($path) : HTTP $code au lieu de $want"; failures=$((failures + 1)); return
  fi
  if ! content_ok "$kind"; then
    echo "ÉCHEC $what ($path) : HTTP $code mais contenu inattendu (${ctype:-sans type}) : $(head -c 200 "$body")"; failures=$((failures + 1)); return
  fi
  echo "OK    $what ($path) : HTTP $code"
}

# 1. Attendre que l'application réponde (propagation ingress / démarrage Spring)
echo "Cible : $BASE (API métier stricte : $STRICT_API)"
deadline=$((SECONDS + WAIT))
until get /actuator/health/readiness && [[ "$code" == "200" ]]; do
  if (( SECONDS >= deadline )); then
    echo "ÉCHEC : readiness indisponible après ${WAIT}s (dernier état : HTTP $code ${detail})"; exit 1
  fi
  echo "en attente de la readiness (HTTP $code ${detail})"; sleep 6
done

# 2. Contrôles
check /actuator/health/readiness 200 "readiness Actuator"   up
check /actuator/prometheus       200 "métriques Prometheus" metrics
check /                          200 "tableau de bord"      html

# 3. API métier : obligatoire sur staging/prod, absente possible sur une feature
for path in /event-stats/summary /participant/all /logistics; do
  if [[ "$STRICT_API" == false ]] && get "$path" && [[ "$code" == "404" ]]; then
    echo "AVERT $path : 404, route absente sur cette feature"
  else
    check "$path" 200 "API $path" json
  fi
done

if (( failures > 0 )); then
  echo "$failures contrôle(s) post-déploiement en échec sur $BASE."; exit 1
fi
echo "Tests post-déploiement réussis sur $BASE."
