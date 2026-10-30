#!/usr/bin/env bash
# Fonctions communes aux scripts Argo CD locaux (sourcé, non exécutable seul).
# Le serveur est joint par « make argocd-ui » (kubectl port-forward) en HTTP clair.

ARGOCD_LOCAL_SERVER="${ARGOCD_LOCAL_SERVER:-localhost:8080}"
# Jamais https:// ni CLI sans --plaintext : la poignée TLS refusée par le serveur
# arrête le port-forward entier (« lost connection to pod »).
ARGOCD_LOCAL_OPTS=(--server "$ARGOCD_LOCAL_SERVER" --plaintext --grpc-web)

# Attend que le tunnel réponde en HTTP clair et que ce soit bien Argo CD.
# Erreurs explicites : port fermé, HTTP inattendu, autre service.
argocd_wait_tunnel() {
  local wait="${ARGOCD_TUNNEL_WAIT_SECONDS:-30}" deadline code rc version
  deadline=$((SECONDS + wait))
  while :; do
    # « && rc=0 || rc=$? » : sous set -e, un échec de curl ne doit pas arrêter l'attente
    code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 3 "http://$ARGOCD_LOCAL_SERVER/healthz" 2>/dev/null)" && rc=0 || rc=$?
    [[ $rc == 0 && "$code" == 200 ]] && break
    if (( SECONDS >= deadline )); then
      case "$rc" in
        7) printf 'Tunnel Argo CD absent sur %s (connexion refusée) après %ss : lancer « make argocd-ui » dans un autre terminal.\n' "$ARGOCD_LOCAL_SERVER" "$wait" >&2 ;;
        28) printf 'Tunnel Argo CD sur %s sans réponse (délai dépassé) après %ss.\n' "$ARGOCD_LOCAL_SERVER" "$wait" >&2 ;;
        0) printf 'http://%s/healthz répond HTTP %s au lieu de 200 : est-ce bien Argo CD ?\n' "$ARGOCD_LOCAL_SERVER" "$code" >&2 ;;
        *) printf 'Tunnel Argo CD sur %s : erreur curl %s.\n' "$ARGOCD_LOCAL_SERVER" "$rc" >&2 ;;
      esac
      return 1
    fi
    sleep 1
  done
  version="$(curl -sS --max-time 5 "http://$ARGOCD_LOCAL_SERVER/api/version" | jq -r '.Version // empty' 2>/dev/null)"
  [[ -n "$version" ]] || { printf 'http://%s/api/version ne renvoie pas une version Argo CD.\n' "$ARGOCD_LOCAL_SERVER" >&2; return 1; }
  printf 'Tunnel prêt : Argo CD %s sur http://%s\n' "$version" "$ARGOCD_LOCAL_SERVER"
}
