# rbw-env

Minimal Bash bridge from an exact [rbw](https://github.com/doy/rbw) folder to environment variables.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/illuwa-soft/rbw-env/v0.4.0/install.sh | bash
```

Installs the fixed `v0.4.0` helper to `${RBW_ENV_INSTALL_DIR:-$HOME/.local/bin}` and its zsh completion to `${RBW_ENV_ZSH_COMPLETION_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions}`, verifies separate checked-in SHA-256 values, and never edits shell profiles. Requires Bash, `curl`, `rbw`, `jq`, `mktemp`, a SHA-256 command (`sha256sum` or `shasum`), and a usable pinentry implementation. Install `jq` separately with your system package manager (for example, `brew install jq` on macOS); the installer never installs packages. If rbw config names a pinentry, that exact command or path must be usable; PATH discovery is used only when no pinentry is configured.

## Bitwarden layout

Create one **Secure Note** per variable in one folder:

- item name: the environment key, matching `^[A-Z_][A-Z0-9_]*$`
- first Notes line: the value
- remaining Notes lines: optional memo, ignored

Only items whose folder name exactly matches the argument are used. Child folders are not traversed.

## Usage

List usable Secure Note names and paths without fetching or printing secret values:

```bash
rbw-env list
.
`-- hermes/
    `-- production/
        |-- API_TOKEN
        `-- DATABASE_URL
```

Read one value by selector:

```bash
rbw-env show hermes/production/API_TOKEN
API_TOKEN="$(rbw-env show hermes/production/API_TOKEN)"
```

`show` deliberately writes the secret value to stdout. Normally use command substitution as above; do not send its output to logs.

### Zsh completion

The normal installer command above installs both `rbw-env` and its zsh completion. You do not need to uninstall an older version first. Add the default completion directory to `fpath`, then initialize zsh completion:

```zsh
fpath=("${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions" $fpath)
autoload -Uz compinit && compinit
```

Start a new shell after the first installation. If zsh still uses a stale completion cache, rebuild it once:

```zsh
rm -f ~/.zcompdump*
exec zsh
```

If you use Oh My Zsh and do not want to add the default directory to `fpath`, install the completion directly into its existing custom completion directory instead:

```zsh
curl -fsSL https://raw.githubusercontent.com/illuwa-soft/rbw-env/v0.4.0/install.sh |
RBW_ENV_ZSH_COMPLETION_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/completions" bash
```

This alternate command is only for completion-path troubleshooting; it is not required when the normal installation already completes `rbw-env show <prefix><TAB>` successfully.

`rbw-env show env/<TAB>` then completes validated metadata paths incrementally. The vault must already be unlocked; completion never prompts or unlocks it.

`list` and `show` are reserved subcommands. To use either word as an exact folder name, disambiguate it with `--folder`, for example `rbw-env --folder list`.

Emit lines for a Hermes command secret source:

```bash
rbw-env hermes/production
```

Stdout uses Hermes command-secret syntax: every raw first-line value is wrapped in one pair of single quotes because Hermes strips one matching outer quote layer without processing escapes. This preserves spaces, `#`, quotes, backslashes, dollars, and `=` for that parser. The output is deliberately **not** universal shell, `source`, or python-dotenv syntax.

Inject variables and replace the process without shell evaluation:

```bash
rbw-env hermes/production -- your-command 'argument with spaces'
```

When the agent is locked, `rbw-env` runs `rbw unlock` once only if standard input is an interactive terminal, then verifies that the agent unlocked before continuing. Noninteractive use fails closed with guidance to unlock manually before retrying:

```bash
rbw unlock
```

`rbw-env` never accepts a master password in arguments or environment variables, creates a secret temp file, enables shell tracing, or includes secret values in its own errors or command arguments.

## Lookup failures

The source version adds a short lookup-failure hint; the pinned `v0.4.0`
installer above still installs the previous release.

`rbw-env` supports Secure Notes, not Login fields. It lists the vault before
selecting a folder or note, so an `invalid mac` error may come from another item;
it does not establish that the requested item is damaged. Use `rbw get` directly
with an item UUID verified in the official client, rather than a name/path.
Keep secret output out of terminal captures, agent output and logs. In rbw 1.15.0,
an absent UUID falls back to name search; direct lookup is not a guaranteed fix.
Stop if it fails. `rbw-env` does not automatically retry or switch items.

## Test

```bash
./test.sh
```

The test uses fake `rbw`, pinentry, and `curl` commands, a thin wrapper around the host `jq`, and standard-library-only `python3` for exact output bytes and PTY checks. Hermes is not required; this tests rbw-env's output contract, not a consumer's parser. Installer fixtures come from the local `v0.4.0` Git tag; runtime tests use the working tree. It never contacts a vault or the network.
