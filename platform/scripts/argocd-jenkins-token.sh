#!/usr/bin/env bash
# =============================================================================
#  Génère le jeton API du compte Argo CD « jenkins » et l'enregistre dans
#  vault_argocd_token, sans jamais l'afficher (ni argument, ni historique, ni log).
#  Prérequis : « make argocd-ui » ouvert, puis « make argocd-login » (admin).
#  Étapes : session admin -> compte jenkins (apiKey, actif) -> RBAC minimal ->
#  génération -> validation avec le jeton lui-même -> écriture dans le Vault.
#  Réglages : ARGOCD_LOCAL_SERVER (localhost:8080), ARGOCD_TOKEN_EXPIRES_IN (aucune).
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=argocd-local.sh
source "$ROOT/scripts/argocd-local.sh"
SERVER="$ARGOCD_LOCAL_SERVER"
OPTS=("${ARGOCD_LOCAL_OPTS[@]}")
for tool in argocd curl jq; do
  command -v "$tool" >/dev/null || { echo "Outil absent : $tool" >&2; exit 1; }
done

fail() { printf 'ÉCHEC : %s\n' "$*" >&2; exit 1; }

# 0. Tunnel prêt (évite la course avec le démarrage de « make argocd-ui »)
argocd_wait_tunnel || exit 1

# 1. Session administrateur sur le serveur visé
info="$(argocd account get-user-info "${OPTS[@]}" -o json)" \
  || fail "get-user-info a échoué sur $SERVER (voir l'erreur du CLI ci-dessus)."
[[ "$(jq -r '.loggedIn' <<<"$info")" == true && "$(jq -r '.username' <<<"$info")" == admin ]] \
  || fail "Session admin absente sur $SERVER : lancer « make argocd-login »."
echo "Session admin vérifiée sur $SERVER."

# 2. Compte jenkins : déclaré, actif, limité aux jetons API
account="$(argocd account get --account jenkins "${OPTS[@]}" -o json)" \
  || fail "Compte jenkins introuvable (accounts.jenkins dans argocd-cm)."
jq -e '.enabled == true' >/dev/null <<<"$account" || fail "Compte jenkins désactivé."
jq -e '(.capabilities // []) == ["apiKey"]' >/dev/null <<<"$account" \
  || fail "Le compte jenkins doit avoir la seule capacité apiKey (reçu : $(jq -c '.capabilities' <<<"$account"))."
existing="$(jq -r '[(.tokens // [])[] | .id] | join(", ")' <<<"$account")"
echo "Compte jenkins : actif, capacité apiKey. Jetons existants : ${existing:-aucun}."

# 3. RBAC : get/sync sur events/*, rien d'autre (lu dans le cluster via kubectl)
if command -v kubectl >/dev/null; then
  can() { argocd admin settings rbac can jenkins "$1" "$2" "$3" --namespace argocd 2>/dev/null | tail -1; }
  [[ "$(can get applications events/events-staging)" == Yes ]] || fail "RBAC : jenkins ne peut pas lire events/events-staging."
  for denied in "delete applications events/events-staging" "get applications default/platform" \
                "update accounts jenkins" "get clusters https://kubernetes.default.svc"; do
    # shellcheck disable=SC2086
    [[ "$(can $denied)" == No ]] || fail "RBAC trop large : jenkins peut « $denied »."
  done
  echo "RBAC vérifié : lecture/synchronisation des Applications events/* uniquement."
fi

# 4. Génération : le jeton reste dans une variable, jamais affiché
id="jenkins-$(date +%Y%m%d-%H%M%S)"
gen=(argocd account generate-token --account jenkins --id "$id" "${OPTS[@]}")
[[ -n "${ARGOCD_TOKEN_EXPIRES_IN:-}" ]] && gen+=(--expires-in "$ARGOCD_TOKEN_EXPIRES_IN")
token="$("${gen[@]}")" || fail "Génération du jeton refusée."
[[ "$token" =~ ^[A-Za-z0-9._-]+$ ]] || { unset token; fail "Réponse inattendue à la génération du jeton."; }
echo "Jeton $id généré (valeur non affichée)."

# 5. Validation avec le jeton lui-même (config CLI vide : la session admin n'intervient pas)
cfg="$(mktemp -d)"; trap 'rm -rf "$cfg"' EXIT
as_jenkins() { ARGOCD_AUTH_TOKEN="$token" argocd "$@" --config "$cfg/config" "${OPTS[@]}"; }
who="$(as_jenkins account get-user-info -o json | jq -r 'select(.loggedIn == true) | .username')" || who=""
if [[ "$who" != jenkins ]]; then
  unset token
  fail "Le jeton $id n'authentifie pas le compte jenkins. Le révoquer : argocd account delete-token --account jenkins $id ${OPTS[*]}"
fi
as_jenkins app get events-staging --refresh -o json | jq -e '.metadata.name == "events-staging"' >/dev/null \
  || echo "AVERTISSEMENT : events-staging illisible avec ce jeton (Application absente ou --refresh refusé)." >&2
echo "Jeton validé : authentifie « jenkins » et lit events-staging."

# 6. Écriture dans le Vault par stdin
printf '%s' "$token" | bash "$ROOT/scripts/vault-set.sh" vault_argocd_token
unset token
echo "Suite : « make configure » (recrée Jenkins avec le credential argocd-token)."
[[ -n "$existing" ]] && echo "Anciens jetons ($existing) : après un build réussi, révoquer avec « argocd account delete-token --account jenkins <id> ${OPTS[*]} »."
exit 0
