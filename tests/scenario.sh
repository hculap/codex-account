# Runs the codex-account test scenario in an isolated CODEX_HOME.
# Invoked by tests/run.sh under each shell: `zsh tests/scenario.sh` / `bash tests/scenario.sh`.
# Exit code 0 when every assertion passes.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CODEX_HOME="$(mktemp -d)"; export CODEX_HOME
ACCOUNTS="$CODEX_HOME/accounts"
FAILS=0
trap 'rm -rf "$CODEX_HOME"' EXIT

source "$ROOT/codex-account.zsh"

pass() { echo "  ok   $1"; }
fail() { echo "  FAIL $1"; FAILS=$((FAILS + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }

jwt() {
  python3 -c '
import base64, json, sys
payload = json.dumps({"email": sys.argv[1], "https://api.openai.com/auth": {"chatgpt_plan_type": sys.argv[2], "chatgpt_account_id": sys.argv[3]}}).encode()
print("eyJhbGciOiJSUzI1NiJ9." + base64.urlsafe_b64encode(payload).decode().rstrip("=") + ".sig")
' "$1" "$2" "$3"
}
login_as() { # login_as <account_id> <email> <plan> <refresh-marker>
  printf '{"auth_mode":"chatgpt","tokens":{"account_id":"%s","id_token":"%s"},"last_refresh":"%s"}' "$1" "$(jwt "$2" "$3" "$1")" "$4" > "$CODEX_HOME/auth.json"
}
refresh_of() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["last_refresh"])' "$1"; }
id_of() { _codex_account_id "$1"; }

echo "codex-account scenario under $(ps -p $$ -o comm= 2>/dev/null || echo shell)"

login_as AAA personal@example.com pro 1
check "save new account" 'codex-account save personal >/dev/null && [[ -f "$ACCOUNTS/personal.json" ]]'
check "save existing name fails" '! codex-account save personal 2>/dev/null'
check "save existing name leaves file untouched" '[[ "$(refresh_of "$ACCOUNTS/personal.json")" == "1" ]]'

login_as AAA personal@example.com pro 2
check "update existing overwrites" 'codex-account update personal >/dev/null && [[ "$(refresh_of "$ACCOUNTS/personal.json")" == "2" ]]'
check "update missing fails" '! codex-account update work 2>/dev/null'

login_as BBB work@example.com plus 3
check "save second account" 'codex-account save work >/dev/null'
LIST="$(codex-account)"
check "list shows logged-in email and plan" '[[ "$LIST" == *"logged in: work@example.com (plus)"* ]]'
check "list marks live account with *" '[[ "$LIST" == *"* work"* && "$LIST" != *"* personal"* ]]'
check "list shows every saved account" '[[ "$LIST" == *"personal@example.com"*"pro"* ]]'
check "list alias works" '[[ "$(codex-account ls)" == "$LIST" ]]'

check "switch to personal" 'codex-account personal >/dev/null && [[ "$(id_of "$CODEX_HOME/auth.json")" == "AAA" ]]'
login_as AAA personal@example.com pro 4
check "switch syncs refreshed tokens back" 'codex-account work >/dev/null && [[ "$(refresh_of "$ACCOUNTS/personal.json")" == "4" ]]'
check "switch lands on target" '[[ "$(id_of "$CODEX_HOME/auth.json")" == "BBB" ]]'
login_as AAA personal@example.com pro 5
check "foreign tokens never overwrite another saved account" 'codex-account personal >/dev/null && [[ "$(id_of "$ACCOUNTS/work.json")" == "BBB" ]]'
check "switch to unknown name fails" '! codex-account nope 2>/dev/null'

check "remove deletes file" 'codex-account remove work >/dev/null && [[ ! -f "$ACCOUNTS/work.json" ]]'
check "remove missing fails" '! codex-account remove work 2>/dev/null'
check "remove without name fails" '! codex-account remove 2>/dev/null'
login_as BBB work@example.com plus 6
check "delete is a synonym for remove" 'codex-account save work >/dev/null && codex-account delete work >/dev/null && [[ ! -f "$ACCOUNTS/work.json" ]]'

check "rejects path traversal name" '! codex-account save ../evil 2>/dev/null && [[ ! -f "$CODEX_HOME/evil.json" ]]'
check "rejects leading-dot name" '! codex-account save .hidden 2>/dev/null'
check "rejects name with spaces" '! codex-account save "a b" 2>/dev/null'

printf '{"tokens":{}}' > "$CODEX_HOME/auth.json"
check "broken auth.json still lists" '[[ "$(codex-account)" == *"logged in: ? (?)"* ]]'
check "help prints usage" '[[ "$(codex-account help)" == *"Usage:"* ]]'
check "version is set" '[[ -n "$CODEX_ACCOUNT_VERSION" ]]'

if [[ "$FAILS" -eq 0 ]]; then echo "all assertions passed"; exit 0; fi
echo "$FAILS assertion(s) failed"; exit 1
