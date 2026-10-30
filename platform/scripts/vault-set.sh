#!/usr/bin/env bash
# =============================================================================
#  Écrit un secret lu sur l'entrée standard dans Ansible Vault, sans jamais
#  l'afficher ni le passer en argument (absent de l'historique et de ps).
#    <commande qui produit le secret> | bash scripts/vault-set.sh vault_<clé>
#  Une copie chiffrée du Vault précédent est gardée dans ansible/.vault-backups/.
#  Réglages : VAULT_FILE, VAULT_PASSWORD_FILE (défaut ansible/.vault_pass).
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY="${1:-}"
VAULT_FILE="${VAULT_FILE:-$ROOT/ansible/group_vars/devops/vault.yml}"
PASS_FILE="${VAULT_PASSWORD_FILE:-$ROOT/ansible/.vault_pass}"
BACKUP_DIR="${VAULT_BACKUP_DIR:-$ROOT/ansible/.vault-backups}"

[[ "$KEY" =~ ^vault_[a-z0-9_]+$ ]] || { echo "Usage : <secret sur stdin> | $0 vault_<clé>" >&2; exit 2; }
[[ ! -t 0 ]] || { echo "Le secret doit arriver par un pipe (stdin), pas par le terminal." >&2; exit 2; }
[[ -s "$VAULT_FILE" ]] || { echo "Vault introuvable : $VAULT_FILE" >&2; exit 1; }
[[ -s "$PASS_FILE" ]] || { echo "Fichier de mot de passe Vault introuvable : $PASS_FILE" >&2; exit 1; }
head -c 14 "$VAULT_FILE" | grep -q '^\$ANSIBLE_VAULT' || { echo "$VAULT_FILE n'est pas chiffré : refus." >&2; exit 1; }

# Programme sur le descripteur 3 : stdin reste réservé au secret
python3 /dev/fd/3 "$KEY" "$VAULT_FILE" "$PASS_FILE" "$BACKUP_DIR" 3<<'PY'
import datetime, os, re, shutil, subprocess, sys, tempfile

key, vault, pass_file, backup_dir = sys.argv[1:5]
secret = sys.stdin.read().strip()
if not secret:
    sys.exit("Secret vide sur stdin : Vault inchangé.")
if re.search(r'[\s"\\]', secret):
    sys.exit("Secret invalide (espace, guillemet ou antislash) : Vault inchangé.")

def vault_cmd(*args, data=None):
    r = subprocess.run(["ansible-vault", *args, "--vault-password-file", pass_file],
                       input=data, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"ansible-vault {args[0]} a échoué : {r.stderr.strip()[:300]}")
    return r.stdout

text = vault_cmd("decrypt", "--output", "-", vault)
line = f'{key}: "{secret}"'
pattern = re.compile(rf"^{re.escape(key)}:.*$", re.MULTILINE)
text, count = pattern.subn(lambda _: line, text, count=1)
if count == 0:
    text = text.rstrip("\n") + "\n" + line + "\n"

os.makedirs(backup_dir, mode=0o700, exist_ok=True)
backup = os.path.join(backup_dir, "vault.yml." + datetime.datetime.now().strftime("%Y%m%d-%H%M%S"))
shutil.copy2(vault, backup)
os.chmod(backup, 0o600)

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(vault), prefix=".vault-", suffix=".tmp")
os.close(fd)
try:
    vault_cmd("encrypt", "--output", tmp, "-", data=text)
    if f'{key}: "{secret}"' not in vault_cmd("decrypt", "--output", "-", tmp).splitlines():
        sys.exit("Relecture du Vault incohérente : Vault inchangé.")
    os.chmod(tmp, os.stat(vault).st_mode & 0o777)
    os.replace(tmp, vault)
finally:
    if os.path.exists(tmp):
        os.remove(tmp)
print(f"{key} enregistré dans {vault} ({len(secret)} caractères, valeur non affichée).")
print(f"Copie chiffrée du Vault précédent : {backup}")
PY
