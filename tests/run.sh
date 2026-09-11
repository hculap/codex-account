#!/usr/bin/env bash
# Runs tests/scenario.sh under every supported shell found on PATH (zsh, bash).
set -euo pipefail

cd "$(dirname "$0")/.."
status=0
ran=0
for shell in zsh bash; do
  command -v "$shell" >/dev/null 2>&1 || { echo "skip: $shell not installed"; continue; }
  echo "== $shell =="
  "$shell" tests/scenario.sh || status=1
  ran=$((ran + 1))
done
[[ "$ran" -gt 0 ]] || { echo "no supported shell found"; exit 1; }
exit "$status"
