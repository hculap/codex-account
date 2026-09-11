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
| `ca help` | Show help. |

`ca` is an alias for `codex-account`. Set `CODEX_ACCOUNT_NO_ALIAS=1` before sourcing to skip it.

### Adding your second account

```bash
ca save personal            # 1. save the account you are logged in with now
codex login --device-auth   # 2. log in to the other account
ca save work                # 3. save it too
ca personal                 # 4. switch back and forth
```

Use `--device-auth` for step 2: it gives you a code to enter in any browser, so you can pick the account instead of the browser silently reusing the ChatGPT session you already have open. Do not run `codex logout` in between. If `codex login` refuses because you are already logged in, move `~/.codex/auth.json` aside first. Your first account is already saved.

## How it works

Saved accounts are plain copies of `auth.json` in `~/.codex/accounts/<name>.json` (mode 600). Switching copies the chosen file over `auth.json`. Before that, the live `auth.json` is copied back into the saved account with the same account id, so tokens Codex refreshed in the meantime are kept. Tokens that belong to a different account are never written into another saved file.

`CODEX_HOME` is honoured, so the tool follows Codex wherever you point it.

## Caveats

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

## License

[MIT](LICENSE)
