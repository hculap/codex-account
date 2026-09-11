#!/usr/bin/env bash
# Installs codex-account: clones (or updates) the repo and wires it into your shell rc.
#   curl -fsSL https://raw.githubusercontent.com/hculap/codex-account/main/install.sh | bash
# Env overrides: CODEX_ACCOUNT_DIR (install dir), CODEX_ACCOUNT_REPO (git URL), CODEX_ACCOUNT_RC (rc file).
set -euo pipefail

repo="${CODEX_ACCOUNT_REPO:-https://github.com/hculap/codex-account.git}"
dest="${CODEX_ACCOUNT_DIR:-$HOME/.codex-account}"

if [[ -d "$dest/.git" ]]; then
  echo "updating $dest"
  git -C "$dest" pull --ff-only --quiet
else
  echo "cloning into $dest"
  git clone --quiet --depth 1 "$repo" "$dest"
fi

if [[ -n "${CODEX_ACCOUNT_RC:-}" ]]; then
  rc="$CODEX_ACCOUNT_RC"
elif [[ "${SHELL:-}" == */bash ]]; then
  rc="$HOME/.bashrc"
else
  rc="$HOME/.zshrc"
fi

line="source \"$dest/codex-account.zsh\""
if [[ -f "$rc" ]] && grep -qF "$line" "$rc"; then
  echo "already wired into $rc"
else
  printf '\n# codex-account: switch ChatGPT accounts in the Codex CLI\n%s\n' "$line" >> "$rc"
  echo "added to $rc"
fi

echo
echo "done. Open a new terminal (or: source \"$rc\"), then:"
echo "  ca save <name>              # save the account you are logged in with now"
echo "  codex login --device-auth   # log in to the other account"
echo "  ca save <other-name>        # save it too"
echo "  ca <name>                   # switch"
