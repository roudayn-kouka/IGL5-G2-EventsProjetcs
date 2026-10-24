#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
elif [[ $# -gt 0 ]]; then
  printf 'Usage : %s [--dry-run]\n' "$0" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMEOUT_SECONDS="${POST_APPLY_TIMEOUT_SECONDS:-900}"
POLL_SECONDS="${POST_APPLY_POLL_SECONDS:-10}"

command -v kubectl >/dev/null || { echo "kubectl est requis." >&2; exit 1; }
command -v dig >/dev/null || { echo "dig est requis." >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 est requis." >&2; exit 1; }

deadline=$((SECONDS + TIMEOUT_SECONDS))
argocd_dns=""
ingress_dns=""
while (( SECONDS < deadline )); do
  argocd_dns="$(kubectl -n argocd get svc argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  ingress_dns="$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  if [[ -n "$argocd_dns" && -n "$ingress_dns" ]]; then
    break
  fi
  printf 'En attente des adresses NLB (Argo CD=%s, ingress=%s)...\n' "${argocd_dns:-en attente}" "${ingress_dns:-en attente}"
  sleep "$POLL_SECONDS"
done

if [[ -z "$argocd_dns" || -z "$ingress_dns" ]]; then
  printf 'Délai dépassé après %s secondes : les deux NLB doivent avoir une adresse.\n' "$TIMEOUT_SECONDS" >&2
  exit 1
fi

ingress_ip="$(dig +short "$ingress_dns" A | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ { print; exit }')"
if [[ -z "$ingress_ip" ]]; then
  printf 'Impossible de résoudre une adresse IPv4 pour %s.\n' "$ingress_dns" >&2
  exit 1
fi

apps_domain="${ingress_ip}.sslip.io"
argocd_server="${argocd_dns}:80"
python3 - "$DRY_RUN" "$argocd_server" "$apps_domain" "$ROOT" <<'PY'
from pathlib import Path
import re
import sys

dry_run = sys.argv[1] == "true"
argocd_server, apps_domain = sys.argv[2:4]
root = Path(sys.argv[4])
updates = {
    "ansible/group_vars/devops/vars.yml": {
        "argocd_server": argocd_server,
        "apps_domain": apps_domain,
    },
    "gitops/platform/apps/20-monitoring.yaml": {
        "hosts": f'["grafana.{apps_domain}"]',
    },
    "gitops/envs/staging/values.yaml": {
        "host": f"staging.{apps_domain}",
    },
    "gitops/envs/prod/values.yaml": {
        "host": f"prod.{apps_domain}",
    },
}

for relative_path, values in updates.items():
    path = root / relative_path
    text = path.read_text(encoding="utf-8")
    for key, value in values.items():
        pattern = re.compile(rf"^(?P<indent>\s*){re.escape(key)}:\s*.*$", re.MULTILINE)
        text, count = pattern.subn(lambda match: f'{match.group("indent")}{key}: "{value}"', text, count=1)
        if count != 1:
            raise SystemExit(f"Clé YAML {key!r} absente ou dupliquée dans {path}")
    if dry_run:
        print(f"[dry-run] {relative_path}")
        for key, value in values.items():
            print(f"  {key}: {value}")
    else:
        path.write_text(text, encoding="utf-8")
        print(f"Mis à jour : {relative_path}")

print(f"Argo CD : http://{argocd_server}")
print(f"Applications : http://{apps_domain}/")
print(f"Grafana : http://grafana.{apps_domain}/")
PY
