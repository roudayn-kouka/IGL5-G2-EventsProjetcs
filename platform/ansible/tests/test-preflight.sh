#!/usr/bin/env bash
# =============================================================================
#  Tests de preflight.yml : inventaire et variables temporaires, connexion locale,
#  aucun Vault ni accès SSH. Usage : bash platform/ansible/tests/test-preflight.sh
# =============================================================================
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cp "$HERE/../preflight.yml" "$T/"; printf "[defaults]\ninterpreter_python = auto_silent\n" > "$T/ansible.cfg"
pass=0; fail=0

run() {   # run <nom> <code attendu> <motif> <var=valeur…> (surcharges des valeurs valides)
  local name="$1" want="$2" pattern="$3"; shift 3
  declare -A v=(
    [ansible_host]=34.202.180.123 [devops_public_ip]=34.202.180.123
    [ecr_registry]=315488743028.dkr.ecr.us-east-1.amazonaws.com [aws_region]=us-east-1
    [argocd_server]=a1b2-c3.elb.us-east-1.amazonaws.com:80 [apps_domain]=44.221.55.161.sslip.io
    [argocd_token]=jeton-de-test
  )
  local kv; for kv in "$@"; do v[${kv%%=*}]="${kv#*=}"; done
  mkdir -p "$T/group_vars/devops"; : > "$T/group_vars/devops/vars.yml"
  printf '[devops]\nusine-devops ansible_host=%s ansible_connection=local\n' "${v[ansible_host]}" > "$T/hosts.ini"
  local k; for k in "${!v[@]}"; do
    [[ "$k" == ansible_host ]] && continue
    [[ "${v[$k]}" == "@absent" ]] || printf '%s: "%s"\n' "$k" "${v[$k]}" >> "$T/group_vars/devops/vars.yml"
  done
  out="$(cd "$T" && ANSIBLE_CONFIG="$T/ansible.cfg" ANSIBLE_NOCOLOR=1 ansible-playbook -i hosts.ini preflight.yml 2>&1)"; code=$?
  (( code != 0 )) && code=1
  if [[ "$code" == "$want" ]] && grep -q -- "$pattern" <<<"$out"; then
    pass=$((pass + 1)); printf 'OK    %s\n' "$name"
  else
    fail=$((fail + 1)); printf 'ÉCHEC %s (code %s, attendu %s)\n%s\n' "$name" "$code" "$want" "$out"
  fi
  if grep -q 'jeton-de-test' <<<"$out"; then
    fail=$((fail + 1)); printf 'ÉCHEC %s : le jeton apparaît dans la sortie\n' "$name"
  fi
}

run "configuration réelle complète"       0 "failed=0"
run "IP d'exemple 203.0.113.10"            1 "valeurs d'exemple" ansible_host=203.0.113.10 devops_public_ip=203.0.113.10
run "compte ECR 000000000000"              1 "valeurs d'exemple" ecr_registry=000000000000.dkr.ecr.us-east-1.amazonaws.com
run "registre ECR hors de la région"       1 "valeurs d'exemple" ecr_registry=315488743028.dkr.ecr.eu-west-3.amazonaws.com
run "inventaire ≠ terraform.yml"           1 "incohérentes"      devops_public_ip=34.202.180.124
run "APPS_DOMAIN absent (runtime.yml)"     1 "make post-apply"   apps_domain=@absent
run "ARGOCD_SERVER vide"                   1 "make post-apply"   argocd_server=
run "APPS_DOMAIN en .local"                1 "make post-apply"   apps_domain=apps.local
run "ARGOCD_SERVER avec schéma"            1 "make post-apply"   argocd_server=http://argocd:80
run "jeton Argo CD vide"                   1 "vault_argocd_token est vide" argocd_token=

printf '\n%s réussi(s), %s échoué(s)\n' "$pass" "$fail"
(( fail == 0 ))
