#!/usr/bin/env bash
# =============================================================================
#  Session admin du CLI Argo CD à travers « make argocd-ui », sans « argocd login ».
#  « argocd login » sonde d'abord le serveur en TLS, même avec --plaintext ; sur ce
#  serveur en HTTP clair la sonde est refusée et kubectl arrête le port-forward,
#  d'où « connection refused » au moment de l'authentification. On appelle donc
#  directement l'API de session (POST /api/v1/session) en HTTP clair, puis on
#  enregistre la session dans la configuration du CLI comme le ferait login.
#  Mot de passe : saisi masqué (ou lu sur stdin hors terminal), jamais en argument.
#  Réglages : ARGOCD_LOCAL_SERVER (localhost:8080), ARGOCD_USERNAME (admin),
#  ARGOCD_CONFIG (~/.config/argocd/config).
# =============================================================================
set -euo pipefail
# shellcheck source=argocd-local.sh
source "$(dirname "${BASH_SOURCE[0]}")/argocd-local.sh"
USERNAME="${ARGOCD_USERNAME:-admin}"
CONFIG="${ARGOCD_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/argocd/config}"
for tool in argocd curl jq python3; do
  command -v "$tool" >/dev/null || { echo "Outil absent : $tool" >&2; exit 1; }
done

argocd_wait_tunnel

if [[ -t 0 ]]; then
  read -rsp "Mot de passe Argo CD de $USERNAME : " ARGOCD_PASSWORD; echo
else
  IFS= read -r ARGOCD_PASSWORD || true
fi
[[ -n "$ARGOCD_PASSWORD" ]] || { echo "Mot de passe vide." >&2; exit 1; }
export ARGOCD_PASSWORD ARGOCD_USERNAME="$USERNAME"

# Corps JSON construit par jq depuis l'environnement, transmis à curl par stdin
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT; body="$work/session.json"
set +e
code="$(jq -n '{username: env.ARGOCD_USERNAME, password: env.ARGOCD_PASSWORD}' \
  | curl -sS -o "$body" -w '%{http_code}' --max-time 15 -H 'Content-Type: application/json' \
         --data-binary @- "http://$ARGOCD_LOCAL_SERVER/api/v1/session")"
rc=$?
set -e
unset ARGOCD_PASSWORD
if (( rc != 0 )); then
  echo "Session impossible : erreur réseau curl $rc vers http://$ARGOCD_LOCAL_SERVER (tunnel coupé ?)." >&2; exit 1
fi
case "$code" in
  200) ;;
  401) echo "Identifiants refusés pour $USERNAME (HTTP 401)." >&2; exit 1 ;;
  429|503) echo "Trop de tentatives : Argo CD limite les connexions (HTTP $code), attendre avant de réessayer." >&2; exit 1 ;;
  *) printf 'Session refusée : HTTP %s — %s\n' "$code" "$(jq -r '.message // empty' "$body" 2>/dev/null | head -c 200)" >&2; exit 1 ;;
esac
token="$(jq -r '.token // empty' "$body")"
[[ -n "$token" ]] || { echo "Réponse de session sans jeton." >&2; exit 1; }

# Vérification avec la session obtenue (aucune sonde TLS : HTTP clair, gRPC-web)
info="$(ARGOCD_AUTH_TOKEN="$token" argocd account get-user-info "${ARGOCD_LOCAL_OPTS[@]}" -o json --config "$work/config")" \
  || { unset token; echo "Session obtenue mais get-user-info a échoué." >&2; exit 1; }
if [[ "$(jq -r '.loggedIn' <<<"$info")" != true || "$(jq -r '.username' <<<"$info")" != "$USERNAME" ]]; then
  unset token; echo "Session non reconnue par le serveur : $(jq -c '{loggedIn, username}' <<<"$info")" >&2; exit 1
fi

# Enregistrement dans la configuration du CLI (même format que « argocd login »), en 0600
printf '%s' "$token" | python3 /dev/fd/3 "$CONFIG" "$ARGOCD_LOCAL_SERVER" "$USERNAME" 3<<'PY'
import os, sys, yaml
path, server, username = sys.argv[1:4]
token = sys.stdin.read()
os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
cfg = {}
if os.path.exists(path):
    with open(path) as f:
        cfg = yaml.safe_load(f) or {}
def upsert(key, name_key, entry):
    items = [i for i in (cfg.get(key) or []) if i.get(name_key) != entry[name_key]]
    cfg[key] = items + [entry]
upsert("servers", "server", {"server": server, "plain-text": True, "grpc-web": True})
upsert("users", "name", {"name": server, "auth-token": token})
upsert("contexts", "name", {"name": server, "server": server, "user": server})
cfg["current-context"] = server
fd = os.open(path + ".tmp", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f:
    yaml.safe_dump(cfg, f, default_flow_style=False)
os.replace(path + ".tmp", path)
os.chmod(path, 0o600)
PY
unset token
printf 'Session %s enregistrée dans %s (contexte %s, jeton non affiché).\n' "$USERNAME" "$CONFIG" "$ARGOCD_LOCAL_SERVER"
argocd account get-user-info "${ARGOCD_LOCAL_OPTS[@]}" --config "$CONFIG"
