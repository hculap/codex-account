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
#   codex-account login <name>   log in to another account safely and save it
#
# Accounts are copies of $CODEX_HOME/auth.json kept in $CODEX_HOME/accounts/.
# Requires python3 (to decode the id_token for email / plan display).
#
# Why `login` exists: every plain `codex login` first revokes the refresh token
# found in auth.json on the server (codex-rs: clear_existing_auth_before_login ->
# logout_with_revoke). A saved copy of that token dies with it. `codex-account login`
# parks auth.json before calling `codex login`, so nothing gets revoked.

CODEX_ACCOUNT_VERSION="1.1.0"
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
# Returns 1 when the live login is not saved under any name.
_codex_account_sync_back() {
  local home="$1" dir="$2" live_id f matched=0
  [[ -f "$home/auth.json" ]] || return 1
  live_id=$(_codex_account_id "$home/auth.json")
  [[ "$live_id" == "?" ]] && return 1
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    if [[ "$(_codex_account_id "$f")" == "$live_id" ]]; then
      cp "$home/auth.json" "$f"
      matched=1
    fi
  done < <(_codex_account_files "$dir")
  [[ "$matched" -eq 1 ]]
}

# Logs in to another account without revoking the current one:
# sync the live login into its saved copy, park auth.json, run `codex login`, save the result.
_codex_account_login() {
  local home="$1" dir="$2" name="$3" parked="$dir/.auth.json.parked" id email plan old_id info
  shift 3
  [[ $# -gt 0 ]] || set -- --device-auth

  if [[ -f "$home/auth.json" ]]; then
    read -r id email plan < <(_codex_account_info "$home/auth.json")
    if [[ "$id" != "?" ]] && ! _codex_account_sync_back "$home" "$dir"; then
      echo "codex-account: the current login ($email) is not saved under any name and would be lost." >&2
      echo "codex-account: run 'codex-account save <name>' first, or 'command codex logout' to discard it." >&2
      return 1
    fi
    mv "$home/auth.json" "$parked" || return 1
  fi

  if command codex login "$@" && [[ -f "$home/auth.json" ]]; then
    rm -f "$parked"
  else
    echo "codex-account: login failed - restoring the previous login" >&2
    [[ -f "$parked" ]] && mv "$parked" "$home/auth.json"
    return 1
  fi

  if [[ -f "$dir/$name.json" ]]; then
    old_id=$(_codex_account_id "$dir/$name.json")
    [[ "$old_id" != "$(_codex_account_id "$home/auth.json")" ]] && echo "codex-account: note: '$name' now points to a different account than before" >&2
  fi
  info=$(_codex_account_store "$home" "$dir" "$name") || return 1
  echo "logged in and saved '$name': $info"
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
  codex-account login <name> [codex login args]
                               log in to another account WITHOUT revoking the
                               current one, then save it (default: --device-auth)
  codex-account help           show this help

Never run plain 'codex login' or 'codex logout' while a saved account is active:
both revoke the current refresh token on the server, killing its saved copy.

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

    login)
      _codex_account_valid_name "$name" || { echo "usage: codex-account login <name> [codex login args]" >&2; return 1; }
      shift 2
      _codex_account_login "$home" "$dir" "$name" "$@"
      return $? ;;

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

# Guard: plain `codex login` / `codex logout` revoke the live refresh token on the
# server, which silently kills its saved copy. Intercept them in interactive shells.
# Disable with CODEX_ACCOUNT_NO_GUARD=1; bypass once with `command codex ...`.
if [[ -z "${CODEX_ACCOUNT_NO_GUARD:-}" ]]; then
  codex() {
    local home; home=$(_codex_account_home)
    case "${1:-}" in
      login)
        if [[ "${2:-}" != "status" && -f "$home/auth.json" ]]; then
          echo "codex-account: 'codex login' would revoke the current account's token on the server." >&2
          echo "codex-account: use 'codex-account login <name>' instead, or 'command codex login' to bypass." >&2
          return 1
        fi ;;
      logout)
        if [[ -f "$home/auth.json" ]]; then
          echo "codex-account: 'codex logout' revokes the current token; its saved copy would stop working." >&2
          echo "codex-account: switch with 'codex-account <name>' instead, or 'command codex logout' to really log out." >&2
          return 1
        fi ;;
    esac
    command codex "$@"
  }
fi
