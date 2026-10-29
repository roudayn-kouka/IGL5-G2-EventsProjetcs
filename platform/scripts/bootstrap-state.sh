#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if command -v pwsh >/dev/null; then
  exec pwsh -NoProfile -File "$ROOT/bootstrap-state.ps1" "$@"
elif command -v powershell.exe >/dev/null && command -v cygpath >/dev/null; then
  exec powershell.exe -NoProfile -File "$(cygpath -w "$ROOT/bootstrap-state.ps1")" "$@"
else
  echo "PowerShell 7 (pwsh), or Git Bash with Windows PowerShell, is required. See docs/ACADEMY-DEMO.md." >&2
  exit 1
fi
