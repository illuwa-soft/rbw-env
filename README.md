# rbw-env

Minimal Bash bridge from an exact [rbw](https://github.com/doy/rbw) folder to environment variables.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/illuwa-soft/rbw-env/v0.1.0/install.sh | bash
```

Installs to `${RBW_ENV_INSTALL_DIR:-$HOME/.local/bin}` and never edits shell profiles. Requires Bash, `curl`, `rbw`, `jq`, and a usable configured or PATH-discoverable pinentry implementation.

## Bitwarden layout

Create one **Secure Note** per variable in one folder:

- item name: the environment key, matching `^[A-Z_][A-Z0-9_]*$`
- first Notes line: the value
- remaining Notes lines: optional memo, ignored

Only items whose folder name exactly matches the argument are used. Child folders are not traversed.

## Usage

Emit dotenv lines for Hermes `secrets.command`:

```bash
rbw-env hermes/production
```

Inject variables and replace the process without shell evaluation:

```bash
rbw-env hermes/production -- your-command 'argument with spaces'
```

Unlock interactively before unattended startup:

```bash
rbw unlock
```

`rbw-env` never unlocks the agent, creates a secret temp file, enables shell tracing, or includes secret values in its own errors or command arguments.

## Test

```bash
./test.sh
```

The test uses fake `rbw`, `jq`, and pinentry commands and never contacts a vault.
