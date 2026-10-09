# codex-account

[![CI](https://github.com/hculap/codex-account/actions/workflows/ci.yml/badge.svg)](https://github.com/hculap/codex-account/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Switch between multiple ChatGPT accounts in the [OpenAI Codex CLI](https://github.com/openai/codex) with one command.

Codex keeps its login in a single file, `~/.codex/auth.json`, and has no built-in account switcher. If you have two subscriptions (personal and work, or two Pro plans), you have to log out and back in every time. `codex-account` saves a copy of that file per account and swaps the active one, while your config, skills, plugins, sessions and memory stay shared.

```text
$ ca
logged in: me@personal.com (pro)
saved:
  * personal       me@personal.com                  pro
    work           me@company.com                   plus

$ ca work
codex -> work: me@company.com (plus)
```

> Unofficial. Not affiliated with OpenAI. It only copies files inside your own `~/.codex`.

## Requirements

- OpenAI Codex CLI, logged in with ChatGPT (`codex login`)
- zsh or bash 3.2+
- `python3` (used to read the email and plan out of the stored token)
- Codex's default file-based credential store (`~/.codex/auth.json`); the keyring store is not supported

## Install

One-liner (clones to `~/.codex-account` and adds a `source` line to your `~/.zshrc` or `~/.bashrc`):

```bash
curl -fsSL https://raw.githubusercontent.com/hculap/codex-account/main/install.sh | bash
```

Manual:

```bash
git clone https://github.com/hculap/codex-account.git ~/.codex-account
echo 'source "$HOME/.codex-account/codex-account.zsh"' >> ~/.zshrc
```

zsh plugin managers work too, the repo ships a `codex-account.plugin.zsh` entry point:

```zsh
zinit light hculap/codex-account          # zinit
antidote bundle hculap/codex-account      # antidote
```

## Usage

| Command | What it does |
|---|---|
| `ca` | List saved accounts with email and plan. `*` marks the one currently logged in. |
| `ca <name>` | Switch to a saved account. |
| `ca save <name>` | Save the current login as `<name>`. Refuses if the name already exists. |
| `ca update <name>` | Overwrite a saved account with the current login. |
| `ca remove <name>` | Delete a saved account. Does not log you out. |
| `ca login <name> [args]` | Log in to another account **without revoking the current one**, then save it. Extra args go to `codex login`; default is `--device-auth`. |
| `ca help` | Show help. |

`ca` is an alias for `codex-account`. Set `CODEX_ACCOUNT_NO_ALIAS=1` before sourcing to skip it.

### Adding your second account

```bash
ca save personal   # 1. save the account you are logged in with now
ca login work      # 2. log in to the other account and save it
ca personal        # 3. switch back and forth
```

Step 2 runs `codex login --device-auth`: you get a code to enter in any browser, so you can pick the account instead of the browser silently reusing the ChatGPT session you already have open. Pass your own arguments to use a different flow, e.g. `ca login work --with-api-key`.

### Why you must not run `codex login` yourself

Every plain `codex login` (browser or device flow) starts by calling `logout_with_revoke`: it sends the refresh token currently in `auth.json` to `https://auth.openai.com/oauth/revoke` and only then logs you in ([source](https://github.com/openai/codex/blob/main/codex-rs/cli/src/login.rs), `clear_existing_auth_before_login`). If you saved that account with `ca save` and then log in to another one the plain way, the saved copy holds a dead token. The next `ca <name>` fails with:

```text
Your access token could not be refreshed because your refresh token was revoked. Please log out and sign in again.
```

`ca login` avoids this by syncing the live login into its saved copy, moving `auth.json` out of the way so Codex finds nothing to revoke, running `codex login`, and saving the result. If the login fails, the previous `auth.json` is restored.

The same revocation happens on `codex logout` and on logging in through the ChatGPT desktop app or an IDE extension that shares `~/.codex`. To catch the CLI cases, sourcing this file defines a small `codex` wrapper in your interactive shell that refuses `codex login` and `codex logout` while an account is live and points you at the safe command. Bypass it once with `command codex ...`, or disable it entirely with `CODEX_ACCOUNT_NO_GUARD=1` before sourcing. Scripts and other programs are not affected; the wrapper only exists in your interactive shell.

If a saved copy did die, log in again with `ca login <name>` (an existing name is overwritten) and everything else keeps working.

## How it works

Saved accounts are plain copies of `auth.json` in `~/.codex/accounts/<name>.json` (mode 600). Switching copies the chosen file over `auth.json`. Before that, the live `auth.json` is copied back into the saved account with the same account id, so tokens Codex refreshed in the meantime are kept. Tokens that belong to a different account are never written into another saved file.

`ca login` is the only command that talks to the network, and only by running `codex login` for you. `CODEX_HOME` is honoured, so the tool follows Codex wherever you point it.

## Caveats

- **Never `codex login` or `codex logout` directly while a saved account is active.** See above. Use `ca login <name>`.
- **Switch when no Codex session is running.** A running session holds its tokens in memory and may write them back to `auth.json` on refresh. Saved copies are protected, the live file is not.
- **Long-lived processes need a restart** to see the new account: the ChatGPT desktop app (it runs a Codex app-server in the background), `codex app-server` daemons, and IDE or agent plugins that embed Codex.
- **Want both accounts at the same time?** Use a separate `CODEX_HOME` instead: `CODEX_HOME=~/.codex-2 codex login --device-auth`, then alias `codex2='CODEX_HOME=$HOME/.codex-2 codex'`. You get full isolation at the cost of a second config, skills and session history.

## Uninstall

```bash
rm -rf ~/.codex-account ~/.codex/accounts
```

and remove the `source` line from your shell rc. Your current login in `~/.codex/auth.json` is untouched.

## Development

```bash
tests/run.sh    # runs the scenario under every installed shell (zsh, bash)
```

## Author

Made by [Szymon Paluch](https://szymonpaluch.com), who builds AI systems that run in production.

## License

[MIT](LICENSE)
