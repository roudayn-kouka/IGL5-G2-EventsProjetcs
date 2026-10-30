#!/usr/bin/env bash
# =============================================================================
#  Tests de argocd-session.sh (make argocd-login) avec un faux serveur Argo CD
#  en HTTP clair qui ENREGISTRE TOUTE POIGNÉE TLS (cause des coupures du tunnel)
#  et un faux CLI argocd. Aucun accès réel.
#  Usage : bash platform/scripts/tests/test-argocd-session.sh  (requiert python3, jq, curl)
# =============================================================================
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$HERE/.." && pwd)"
T="$(mktemp -d)"
SERVER_PID=""
trap 'kill $SERVER_PID 2>/dev/null; rm -rf "$T"' EXIT
pass=0; fail=0
PASSWORD="mdp-factice-$RANDOM"
SESSION="session-factice-$RANDOM$RANDOM"
PORT=$((20000 + RANDOM % 20000))

ok() { pass=$((pass + 1)); printf 'OK    %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf 'ÉCHEC %s\n%s\n' "$1" "${2:-}"; }

cat > "$T/server.py" <<'PY'
import json, socket, sys, threading, time
port, password, session, mode, delay, log = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], float(sys.argv[5]), sys.argv[6]
time.sleep(delay)                      # tunnel qui démarre en retard
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", int(port))); s.listen(20)
def reply(c, code, body, ctype="application/json"):
    c.sendall(f"HTTP/1.1 {code} X\r\nContent-Type: {ctype}\r\nContent-Length: {len(body)}\r\nConnection: close\r\n\r\n".encode() + body)
def handle(c):
    data = c.recv(65536)
    if data[:2] == b"\x16\x03":
        open(log, "a").write("TLS\n"); c.close(); return
    head, _, body = data.partition(b"\r\n\r\n")
    line = head.split(b"\r\n")[0].decode()
    open(log, "a").write(line + "\n")
    if mode == "pas-argocd":
        reply(c, 404, b"not found", "text/plain")
    elif line.startswith("GET /healthz"):
        reply(c, 200, b"ok", "text/plain")
    elif line.startswith("GET /api/version"):
        reply(c, 200, b'{"Version":"v2.13.2+fake"}')
    elif line.startswith("POST /api/v1/session"):
        try: req = json.loads(body)
        except Exception: req = {}
        if req.get("username") == "admin" and req.get("password") == password:
            reply(c, 200, json.dumps({"token": session}).encode())
        else:
            reply(c, 401, b'{"message":"invalid username or password"}')
    else:
        reply(c, 404, b"{}")
    c.close()
while True:
    c, _ = s.accept(); threading.Thread(target=handle, args=(c,)).start()
PY

mkdir -p "$T/bin"
cat > "$T/bin/argocd" <<EOF
#!/usr/bin/env bash
# Faux CLI : get-user-info accepte la session par ARGOCD_AUTH_TOKEN ou par --config
tok="\${ARGOCD_AUTH_TOKEN:-}"; cfg=""; json=false; prev=""
for a in "\$@"; do [[ "\$prev" == --config ]] && cfg="\$a"; [[ "\$prev" == -o && "\$a" == json ]] && json=true; prev="\$a"; done
if [[ -z "\$tok" && -f "\$cfg" ]]; then tok="\$(sed -nE 's/.*auth-token: (.*)/\1/p' "\$cfg")"; fi
[[ "\$1 \$2" == "account get-user-info" ]] || { echo "inattendu : \$*" >&2; exit 99; }
if [[ "\$tok" == "$SESSION" ]]; then
  \$json && echo '{"loggedIn":true,"username":"admin"}' || printf 'Logged In: true\nUsername: admin\n'
else
  \$json && echo '{"loggedIn":false}' || echo 'Logged In: false'
fi
EOF
chmod +x "$T/bin/argocd"

start_server() {   # start_server <mode> <délai>
  kill $SERVER_PID 2>/dev/null; wait $SERVER_PID 2>/dev/null; : > "$T/requests.log"
  python3 "$T/server.py" "$PORT" "$PASSWORD" "$SESSION" "$1" "$2" "$T/requests.log" & SERVER_PID=$!
}
stop_server() { kill $SERVER_PID 2>/dev/null; wait $SERVER_PID 2>/dev/null; SERVER_PID=""; }

login() {   # login <mot de passe> [VAR=valeur…]
  local pw="$1"; shift
  out="$(printf '%s\n' "$pw" | env PATH="$T/bin:$PATH" HOME="$T/home" ARGOCD_LOCAL_SERVER="127.0.0.1:$PORT" \
         ARGOCD_TUNNEL_WAIT_SECONDS=8 "$@" bash "$SCRIPTS/argocd-session.sh" 2>&1)"; code=$?
}
check_common() {   # pas de TLS envoyé, pas de secret affiché
  grep -q '^TLS$' "$T/requests.log" && ko "$1 : une poignée TLS a été envoyée au serveur HTTP"
  grep -q -- "$PASSWORD" <<<"$out" && ko "$1 : le mot de passe apparaît dans la sortie"
  grep -q -- "$SESSION" <<<"$out" && ko "$1 : le jeton de session apparaît dans la sortie"
  return 0
}
CFG="$T/home/.config/argocd/config"

# 1. Parcours nominal
start_server argocd 0; sleep 0.5; rm -rf "$T/home"
login "$PASSWORD"
if [[ $code == 0 ]] && grep -q 'Logged In: true' <<<"$out" && grep -q "auth-token: $SESSION" "$CFG" 2>/dev/null; then
  ok "session ouverte, enregistrée et vérifiée"; else ko "parcours nominal (code $code)" "$out"; fi
[[ "$(stat -c %a "$CFG" 2>/dev/null)" == 600 ]] && ok "configuration CLI en 0600" || ko "permissions de la configuration CLI"
python3 -c 'import sys,yaml; c=yaml.safe_load(open(sys.argv[1])); s=c["servers"][0]; sys.exit(0 if s["plain-text"] and s["grpc-web"] else 1)' "$CFG" \
  && ok "contexte en plain-text + grpc-web (le CLI ne tentera pas TLS)" || ko "contexte sans plain-text/grpc-web"
grep -q 'POST /api/v1/session' "$T/requests.log" && ok "session demandée en HTTP clair" || ko "pas de POST /api/v1/session"
check_common "parcours nominal"

# 2. Course : le tunnel arrive 3 s après le lancement du login
start_server argocd 3; rm -rf "$T/home"
login "$PASSWORD"
[[ $code == 0 ]] && grep -q 'Tunnel prêt' <<<"$out" && ok "attente du tunnel lent puis connexion" || ko "course tunnel/login (code $code)" "$out"
check_common "tunnel lent"

# 3. Mot de passe refusé : erreur explicite, configuration non créée
start_server argocd 0; sleep 0.5; rm -rf "$T/home"
login "mauvais-$RANDOM"
[[ $code != 0 && ! -f "$CFG" ]] && grep -q 'HTTP 401' <<<"$out" && ok "identifiants refusés : HTTP 401, rien enregistré" || ko "mauvais mot de passe (code $code)" "$out"
check_common "mot de passe refusé"

# 4. Configuration existante : autres contextes conservés
mkdir -p "$(dirname "$CFG")"
printf 'contexts:\n- name: autre\n  server: autre:443\n  user: autre\ncurrent-context: autre\nservers:\n- server: autre:443\nusers:\n- name: autre\n  auth-token: x\n' > "$CFG"; chmod 600 "$CFG"
login "$PASSWORD"
python3 -c 'import sys,yaml; c=yaml.safe_load(open(sys.argv[1])); n=[x["name"] for x in c["contexts"]]; sys.exit(0 if "autre" in n and c["current-context"]!="autre" else 1)' "$CFG" \
  && ok "contexte existant conservé, nouveau contexte courant" || ko "fusion de la configuration" "$out"

# 5. Tunnel absent : erreur explicite (pas de masquage)
stop_server; rm -rf "$T/home"
login "$PASSWORD" ARGOCD_TUNNEL_WAIT_SECONDS=2
[[ $code != 0 ]] && grep -q 'make argocd-ui' <<<"$out" && grep -q 'connexion refusée' <<<"$out" \
  && ok "tunnel absent : connexion refusée explicite" || ko "tunnel absent (code $code)" "$out"

# 6. Autre service sur le port : refusé
start_server pas-argocd 0; sleep 0.5; rm -rf "$T/home"
login "$PASSWORD" ARGOCD_TUNNEL_WAIT_SECONDS=2
[[ $code != 0 && ! -f "$CFG" ]] && grep -q 'HTTP 404' <<<"$out" && ok "service inattendu sur le port : refusé" || ko "service inattendu (code $code)" "$out"
check_common "service inattendu"

# 7. Mot de passe vide
start_server argocd 0; sleep 0.5; rm -rf "$T/home"
login ""
[[ $code != 0 ]] && grep -q 'Mot de passe vide' <<<"$out" && ok "mot de passe vide refusé" || ko "mot de passe vide (code $code)" "$out"
stop_server

printf '\n%s réussi(s), %s échoué(s)\n' "$pass" "$fail"
(( fail == 0 ))
