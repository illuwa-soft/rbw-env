# rbw-env

Minimal Bash bridge from an exact [rbw](https://github.com/doy/rbw) folder to environment variables.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/illuwa-soft/rbw-env/v0.1.3/install.sh | bash
```

Installs the fixed `v0.1.3` helper to `${RBW_ENV_INSTALL_DIR:-$HOME/.local/bin}`, verifies its checked-in SHA-256, and never edits shell profiles. Requires Bash, `curl`, `rbw`, `jq`, `mktemp`, a SHA-256 command (`sha256sum` or `shasum`), and a usable pinentry implementation. If rbw config names a pinentry, that exact command or path must be usable; PATH discovery is used only when no pinentry is configured.

## Bitwarden layout

Create one **Secure Note** per variable in one folder:

- item name: the environment key, matching `^[A-Z_][A-Z0-9_]*$`
- first Notes line: the value
- remaining Notes lines: optional memo, ignored

Only items whose folder name exactly matches the argument are used. Child folders are not traversed.

## Usage

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

## Test

```bash
./test.sh
```

The dependency-free test uses fake `rbw`, pinentry, and `curl` commands, a thin wrapper around the host `jq`, and the installed Hermes parser. It never contacts a vault or the network.
