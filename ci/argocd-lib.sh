#!/usr/bin/env bash
# Fonctions Argo CD communes (sourcé par deploy-preflight.sh et argocd-wait.sh).

# Traduit une erreur du CLI argocd en diagnostic exploitable (sur stderr).
# Retourne 0 si l'erreur est transitoire (nouvel essai pertinent), 1 sinon.
argocd_explain() {
  local err="$1" kind hint transient=1
  case "$err" in
    *"server address unspecified"*)
      kind="CONFIGURATION"; hint="ARGOCD_SERVER est vide : make post-apply puis make configure." ;;
    *"no such host"*|*"server misbehaving"*)
      kind="DNS"; hint="Le nom ${ARGOCD_SERVER:-?} ne se résout pas depuis Jenkins (NLB interne : Jenkins doit être dans le VPC)." ;;
    *"x509"*|*"certificate"*|*"tls:"*|*"first record does not look like a TLS handshake"*)
      kind="TLS"; hint="Argo CD sert du HTTP (server.insecure) : ARGOCD_OPTS doit contenir --plaintext, ou fournir le bon certificat." ;;
    *"connection refused"*|*"i/o timeout"*|*"context deadline exceeded"*|*"connection reset"*|*"Unavailable"*)
      kind="RÉSEAU"; transient=0
      hint="Argo CD injoignable : groupe de sécurité / loadBalancerSourceRanges du NLB interne (CIDR du VPC) ou serveur en redémarrage." ;;
    *"Unauthenticated"*|*"invalid session"*|*"token is expired"*|*"account jenkins does not have"*|*"no session information"*)
      kind="AUTHENTIFICATION"; hint="Jeton argocd-token invalide ou expiré : régénérer (make argocd-token) et mettre à jour le credential." ;;
    *"PermissionDenied"*|*"permission denied"*)
      kind="AUTORISATION"; hint="Le compte jenkins n'a pas les droits get/sync sur events/* (policy.csv d'Argo CD)." ;;
    *"NotFound"*|*"not found"*)
      kind="APPLICATION ABSENTE"; transient=0
      hint="L'ApplicationSet n'a pas (encore) créé l'Application : il crée events-<env> à partir de envs/<env>/config.json sur ${GITOPS_BRANCH:-gitops}." ;;
    "")
      kind="RÉPONSE VIDE"; hint="Le CLI n'a rien renvoyé." ;;
    *)
      kind="INCONNUE"; hint="Voir le message du CLI ci-dessus." ;;
  esac
  printf 'Argo CD — erreur %s : %s\n  %s\n' "$kind" "$(printf '%s' "$err" | tr '\n' ' ' | head -c 400)" "$hint" >&2
  return "$transient"
}

# Index de la source « values » (ref: values) d'une Application multi-source, ou -1.
argocd_values_index() {
  jq -r '[(.spec.sources // [])[] | .ref == "values"] | index(true) // -1' <<<"$1"
}

# Vérifie que la source des valeurs lit le dépôt et la branche où Jenkins pousse.
argocd_check_values_source() {
  local json="$1" app="$2" idx repo rev
  idx="$(argocd_values_index "$json")"
  if [[ "$idx" == "-1" ]]; then
    printf 'Argo CD : %s n a pas de source « ref: values » (Application multi-source attendue).\n' "$app" >&2
    return 1
  fi
  repo="$(jq -r --argjson i "$idx" '.spec.sources[$i].repoURL' <<<"$json")"
  rev="$(jq -r --argjson i "$idx" '.spec.sources[$i].targetRevision' <<<"$json")"
  if [[ "$repo" != *"${PLATFORM_REPO}"* || "$rev" != "$GITOPS_BRANCH" ]]; then
    printf 'Argo CD : %s lit les valeurs sur %s@%s, mais Jenkins pousse sur %s@%s.\n' \
      "$app" "$repo" "$rev" "$PLATFORM_REPO" "$GITOPS_BRANCH" >&2
    echo "  Corriger l'ApplicationSet (platform/gitops/platform/apps/40-events-environments.yaml) : la révision poussée ne serait jamais déployée." >&2
    return 1
  fi
  printf 'Argo CD : %s lit les valeurs sur %s@%s (source %s).\n' "$app" "$repo" "$rev" "$idx"
}
