# codex-account - switch between multiple ChatGPT accounts in the OpenAI Codex CLI.
# https://github.com/hculap/codex-account
#
# Works in zsh and bash (3.2+). Source this file from your shell rc:
#   source /path/to/codex-account.zsh
#
#   codex-account                list saved accounts (* = currently logged in)
#   codex-account <name>         switch to a saved account
#   codex-account save <name>    save the current login (fails if <name> exists)
#   codex-account update <name>  overwrite a saved account with the current login
#   codex-account remove <name>  delete a saved account (does not log out)
#
# Accounts are copies of $CODEX_HOME/auth.json kept in $CODEX_HOME/accounts/.
# Requires python3 (to decode the id_token for email / plan display).

CODEX_ACCOUNT_VERSION="1.0.0"
[[ -z "${CODEX_ACCOUNT_NO_ALIAS:-}" ]] && alias ca='codex-account'

_codex_account_home() { printf '%s\n' "${CODEX_HOME:-$HOME/.codex}"; }

# Prints "account_id email plan" decoded from the id_token inside an auth.json.
# Unknown fields print as "?" so callers never fail on a broken file.
_codex_account_info() {
  python3 - "$1" 2>/dev/null <<'PY' || printf '? ? ?\n'
import base64
import json
import sys

try:
    data = json.load(open(sys.argv[1]))
except Exception:
    print("? ? ?")
    sys.exit(0)

tokens = data.get("tokens") or {}
claims = {}
try:
    payload = tokens.get("id_token", "").split(".")[1]
    claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
except Exception:
    pass

auth = claims.get("https://api.openai.com/auth") or {}
print(
    tokens.get("account_id") or "?",
    claims.get("email") or "?",
    auth.get("chatgpt_plan_type") or "?",
)
PY
}

_codex_account_id() { _codex_account_info "$1" | cut -d' ' -f1; }

# Account names become file names: letters, digits, dot, dash, underscore; no leading dot.
_codex_account_valid_name() {
  case "$1" in
    ""|.*|*[!A-Za-z0-9._-]*) return 1 ;;
  esac
  return 0
}

# Lists saved account files, one path per line, sorted.
_codex_account_files() {
  find "$1" -maxdepth 1 -name '*.json' 2>/dev/null | sort
}

# Copies the live auth.json back into every saved account with the same account id,
# so tokens refreshed by Codex are not lost when switching away.
_codex_account_sync_back() {
  local home="$1" dir="$2" live_id f
  [[ -f "$home/auth.json" ]] || return 0
  live_id=$(_codex_account_id "$home/auth.json")
  [[ "$live_id" == "?" ]] && return 0
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    if [[ "$(_codex_account_id "$f")" == "$live_id" ]]; then
      cp "$home/auth.json" "$f"
    fi
  done < <(_codex_account_files "$dir")
}

_codex_account_store() {
  local home="$1" dir="$2" name="$3" id email plan
  [[ -f "$home/auth.json" ]] || { echo "codex-account: no $home/auth.json - run 'codex login' first" >&2; return 1; }
  cp "$home/auth.json" "$dir/$name.json" && chmod 600 "$dir/$name.json" || return 1
  read -r id email plan < <(_codex_account_info "$dir/$name.json")
  printf '%s (%s)\n' "$email" "$plan"
}

_codex_account_list() {
  local home="$1" dir="$2" live_id live_email live_plan f name id email plan mark
  read -r live_id live_email live_plan < <(_codex_account_info "$home/auth.json")
  echo "logged in: $live_email ($live_plan)"
  echo "saved:"
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    name=${f##*/}; name=${name%.json}
    read -r id email plan < <(_codex_account_info "$f")
    mark=" "; [[ "$id" == "$live_id" ]] && mark="*"
    printf '  %s %-14s %-32s %s\n' "$mark" "$name" "$email" "$plan"
  done < <(_codex_account_files "$dir")
}

_codex_account_help() {
  cat <<EOT
codex-account $CODEX_ACCOUNT_VERSION - switch between ChatGPT accounts in the Codex CLI

Usage:
  codex-account                list saved accounts (* = currently logged in)
  codex-account <name>         switch to a saved account
  codex-account save <name>    save the current login as <name> (fails if it exists)
  codex-account update <name>  overwrite a saved account with the current login
  codex-account remove <name>  delete a saved account (does not log out)
  codex-account help           show this help

Accounts are stored in \$CODEX_HOME/accounts (default: ~/.codex/accounts).
Alias: ca (set CODEX_ACCOUNT_NO_ALIAS=1 before sourcing to disable).
EOT
}

codex-account() {
  local cmd="${1:-}" name="${2:-}" home dir info id email plan
  home=$(_codex_account_home); dir="$home/accounts"
  mkdir -p "$dir"

  case "$cmd" in
    ""|list|ls)
      _codex_account_list "$home" "$dir"
      return 0 ;;

    help|-h|--help)
      _codex_account_help
      return 0 ;;

    save)
      _codex_account_valid_name "$name" || { echo "usage: codex-account save <name>" >&2; return 1; }
      [[ -f "$dir/$name.json" ]] && { echo "codex-account: '$name' already exists - use: codex-account update $name" >&2; return 1; }
      info=$(_codex_account_store "$home" "$dir" "$name") || return 1
      echo "saved '$name': $info"
      return 0 ;;

    update)
      _codex_account_valid_name "$name" || { echo "usage: codex-account update <name>" >&2; return 1; }
      [[ -f "$dir/$name.json" ]] || { echo "codex-account: no account '$name' - use: codex-account save $name" >&2; return 1; }
      info=$(_codex_account_store "$home" "$dir" "$name") || return 1
      echo "updated '$name': $info"
      return 0 ;;

    remove|delete|rm)
      _codex_account_valid_name "$name" || { echo "usage: codex-account remove <name>" >&2; return 1; }
      [[ -f "$dir/$name.json" ]] || { echo "codex-account: no account '$name'" >&2; return 1; }
      read -r id email plan < <(_codex_account_info "$dir/$name.json")
      rm -f "$dir/$name.json" || return 1
      echo "removed '$name': $email ($plan)"
      return 0 ;;
  esac

  # Anything else is a name to switch to.
  name="$cmd"
  _codex_account_valid_name "$name" || { echo "codex-account: invalid account name '$name'" >&2; return 1; }
  [[ -f "$dir/$name.json" ]] || { echo "codex-account: no account '$name' (see: codex-account list)" >&2; return 1; }

  _codex_account_sync_back "$home" "$dir"
  cp "$dir/$name.json" "$home/auth.json" && chmod 600 "$home/auth.json" || return 1
  read -r id email plan < <(_codex_account_info "$home/auth.json")
  echo "codex -> $name: $email ($plan)"
}
