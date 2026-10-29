#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# One implementation for PowerShell, Git Bash and Linux with PowerShell 7.
case "${1:-}" in
  "") action=Destroy ;;
  --preview) action=PreviewDestroy ;;
  --verify) action=Verify ;;
  *) echo "Usage: $0 [--preview|--verify]" >&2; exit 2 ;;
esac
if command -v pwsh >/dev/null; then
  exec pwsh -NoProfile -File "$ROOT/academy.ps1" -Action "$action"
elif command -v powershell.exe >/dev/null && command -v cygpath >/dev/null; then
  exec powershell.exe -NoProfile -File "$(cygpath -w "$ROOT/academy.ps1")" -Action "$action"
else
  echo "PowerShell 7 (pwsh), or Git Bash with Windows PowerShell, is required. See docs/ACADEMY-DEMO.md." >&2
  exit 1
fi
