#!/usr/bin/env bash
# =============================================================================
#  Tests de vault-set.sh et argocd-jenkins-token.sh : Vault et mot de passe
#  temporaires, faux CLI argocd/kubectl (aucun accès réel). Vérifie aussi que
#  le secret n'apparaît jamais dans la sortie.
#  Usage : bash platform/scripts/tests/test-secret-tools.sh  (requiert ansible-vault, jq)
# =============================================================================
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$HERE/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
SECRET="jeton-factice-de-test-$RANDOM$RANDOM"   # généré : aucun littéral à forte entropie

ok()  { pass=$((pass + 1)); printf 'OK    %s\n' "$1"; }
ko()  { fail=$((fail + 1)); printf 'ÉCHEC %s\n%s\n' "$1" "${2:-}"; }
leak() { if grep -q "$SECRET" <<<"$1"; then ko "$2 : le secret apparaît dans la sortie"; fi; }

new_vault() {
  printf 'test-pass\n' > "$T/pass"; chmod 600 "$T/pass"
  printf 'vault_github_user: "u"\nvault_argocd_token: ""   # commentaire\nvault_sonar_token: ""\n' \
    | ansible-vault encrypt --vault-password-file "$T/pass" --output "$T/vault.yml" - >/dev/null 2>&1
  rm -rf "$T/backups"
}
vault_get() {   # vault_get <clé> -> valeur
  ansible-vault decrypt --vault-password-file "$T/pass" --output - "$T/vault.yml" 2>/dev/null \
    | sed -nE "s/^$1: \"(.*)\".*/\1/p"
}
export VAULT_FILE="$T/vault.yml" VAULT_PASSWORD_FILE="$T/pass" VAULT_BACKUP_DIR="$T/backups"

# --- vault-set.sh -------------------------------------------------------------------
new_vault
out="$(printf '%s\n' "$SECRET" | bash "$SCRIPTS/vault-set.sh" vault_argocd_token 2>&1)"; code=$?
if [[ $code == 0 && "$(vault_get vault_argocd_token)" == "$SECRET" && "$(vault_get vault_github_user)" == u ]]; then
  ok "vault-set : clé remplacée, autres clés intactes"; else ko "vault-set : remplacement" "$out"; fi
leak "$out" "vault-set"
head -c 14 "$T/vault.yml" | grep -q '^\$ANSIBLE_VAULT' && ok "vault-set : Vault toujours chiffré" || ko "vault-set : Vault en clair"
[[ "$(ls "$T/backups" | wc -l)" == 1 ]] && ok "vault-set : copie chiffrée de sauvegarde" || ko "vault-set : pas de sauvegarde"

out="$(printf 'abc\n' | bash "$SCRIPTS/vault-set.sh" vault_nouvelle_cle 2>&1)"
[[ "$(vault_get vault_nouvelle_cle)" == abc ]] && ok "vault-set : clé absente ajoutée" || ko "vault-set : ajout" "$out"

before="$(sha256sum "$T/vault.yml")"
out="$(printf '' | bash "$SCRIPTS/vault-set.sh" vault_argocd_token 2>&1)"; code=$?
[[ $code != 0 && "$(sha256sum "$T/vault.yml")" == "$before" ]] && ok "vault-set : secret vide refusé, Vault inchangé" || ko "vault-set : secret vide" "$out"
out="$(printf 'a b\n' | bash "$SCRIPTS/vault-set.sh" vault_argocd_token 2>&1)"; code=$?
[[ $code != 0 && "$(sha256sum "$T/vault.yml")" == "$before" ]] && ok "vault-set : secret avec espace refusé" || ko "vault-set : espace" "$out"
out="$(printf 'x\n' | bash "$SCRIPTS/vault-set.sh" 'mauvaise-cle' 2>&1)"; code=$?
[[ $code == 2 ]] && ok "vault-set : nom de clé invalide refusé" || ko "vault-set : clé invalide" "$out"
out="$(printf 'x\n' | VAULT_PASSWORD_FILE="$T/absent" bash "$SCRIPTS/vault-set.sh" vault_argocd_token 2>&1)"; code=$?
[[ $code != 0 && "$(sha256sum "$T/vault.yml")" == "$before" ]] && ok "vault-set : mot de passe Vault absent" || ko "vault-set : pass absent" "$out"
printf 'wrong\n' > "$T/wrongpass"
out="$(printf 'x\n' | VAULT_PASSWORD_FILE="$T/wrongpass" bash "$SCRIPTS/vault-set.sh" vault_argocd_token 2>&1)"; code=$?
[[ $code != 0 && "$(sha256sum "$T/vault.yml")" == "$before" ]] && ok "vault-set : mauvais mot de passe, Vault inchangé" || ko "vault-set : mauvais pass" "$out"

# --- argocd-jenkins-token.sh avec faux CLI ---------------------------------------------
mkdir -p "$T/bin"
cat > "$T/bin/argocd" <<EOF
#!/usr/bin/env bash
# Faux CLI : refuse toute commande réseau sans --plaintext (comme le serveur réel)
args=" \$* "
if [[ "\$1" != admin && "\$args" != *" --plaintext "* ]]; then echo "connection refused" >&2; exit 20; fi
case "\$1 \$2" in
  "account get-user-info")
    if [[ -n "\${ARGOCD_AUTH_TOKEN:-}" ]]; then
      [[ "\$ARGOCD_AUTH_TOKEN" == "$SECRET" && "\${FAKE_TOKEN_OK:-1}" == 1 ]] \
        && echo '{"loggedIn":true,"username":"jenkins"}' || echo '{"loggedIn":false}'
    else
      [[ "\${FAKE_ADMIN:-1}" == 1 ]] && echo '{"loggedIn":true,"username":"admin"}' || echo '{"loggedIn":false}'
    fi ;;
  "account get") echo "{\"name\":\"jenkins\",\"enabled\":true,\"capabilities\":\${FAKE_CAPS:-[\"apiKey\"]},\"tokens\":\${FAKE_TOKENS:-[]}}" ;;
  "account generate-token") printf '%s\n' "$SECRET" ;;
  "app get") echo '{"metadata":{"name":"events-staging"}}' ;;
  "admin settings")
    case "\$6 \$7 \$8" in
      "get applications events/events-staging") echo Yes ;;
      "delete applications events/events-staging") echo "\${FAKE_RBAC_DELETE:-No}" ;;
      *) echo No ;;
    esac ;;
  *) echo "inattendu : \$*" >&2; exit 99 ;;
esac
EOF
printf '#!/bin/sh\nexit 0\n' > "$T/bin/kubectl"
chmod +x "$T/bin/"*

tok() {   # tok <nom> <code attendu> <motif> [VAR=valeur…]
  local name="$1" want="$2" pattern="$3"; shift 3
  new_vault
  out="$(env PATH="$T/bin:$PATH" "$@" bash "$SCRIPTS/argocd-jenkins-token.sh" 2>&1)"; code=$?
  (( code != 0 )) && code=1
  if [[ $code == "$want" ]] && grep -q -- "$pattern" <<<"$out"; then ok "token : $name"; else ko "token : $name (code $code)" "$out"; fi
  leak "$out" "token : $name"
}
tok "parcours complet, jeton dans le Vault"   0 "vault_argocd_token enregistré"
[[ "$(vault_get vault_argocd_token)" == "$SECRET" ]] && ok "token : valeur exacte dans le Vault" || ko "token : valeur absente du Vault"
tok "session admin absente"                     1 "make argocd-login"        FAKE_ADMIN=0
tok "compte avec capacité login refusé"         1 "seule capacité apiKey"    'FAKE_CAPS=["apiKey","login"]'
tok "RBAC trop large refusé"                    1 "RBAC trop large"          FAKE_RBAC_DELETE=Yes
tok "jeton non valide : Vault inchangé"         1 "n'authentifie pas"        FAKE_TOKEN_OK=0
[[ -z "$(vault_get vault_argocd_token)" ]] && ok "token : Vault vide après jeton invalide" || ko "token : Vault modifié malgré l'échec"
tok "anciens jetons signalés"                   0 "Anciens jetons (jenkins-old)" 'FAKE_TOKENS=[{"id":"jenkins-old"}]'

printf '\n%s réussi(s), %s échoué(s)\n' "$pass" "$fail"
(( fail == 0 ))
