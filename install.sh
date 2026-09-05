#!/usr/bin/env bash
set -eu

fail() { printf 'rbw-env installer: %s\n' "$1" >&2; exit 1; }
for dependency in curl rbw; do
  command -v "$dependency" >/dev/null 2>&1 || fail "required command not found: $dependency"
done
# shellcheck disable=SC2016 # Backticks are literal installation guidance.
command -v jq >/dev/null 2>&1 || fail 'required command not found: jq; install jq with your system package manager (for example, `brew install jq` on macOS), then retry'
command -v mktemp >/dev/null 2>&1 || fail 'required command not found: mktemp'

rbw=$(command -v rbw)
jq=$(command -v jq)
pinentry=''
configured=$("$rbw" config show 2>/dev/null | "$jq" -er '.pinentry | strings | select(length > 0)' 2>/dev/null || :)
if [ -n "$configured" ]; then
  if case "$configured" in */*) [ -x "$configured" ];; *) command -v "$configured" >/dev/null 2>&1;; esac; then
    pinentry=$configured
  else
    # shellcheck disable=SC2016 # Backticks are literal remediation guidance.
    fail 'configured rbw pinentry is unusable; update it with `rbw config set pinentry <command-or-path>`'
  fi
else
  for candidate in pinentry pinentry-curses pinentry-tty pinentry-mac; do
    if command -v "$candidate" >/dev/null 2>&1; then pinentry=$candidate; break; fi
  done
fi
[ -n "$pinentry" ] || fail 'no usable pinentry found (configure rbw pinentry or install one)'

install_dir=${RBW_ENV_INSTALL_DIR:-"$HOME/.local/bin"}
destination=$install_dir/rbw-env
umask 077
mkdir -p "$install_dir"
pending=$(mktemp "$install_dir/.rbw-env.XXXXXX") || fail 'could not create installer staging file'
trap 'rm -f "$pending"' EXIT HUP INT TERM
if ! curl -fsSL "https://raw.githubusercontent.com/illuwa-soft/rbw-env/v0.3.0/rbw-env" -o "$pending"; then
  fail 'download failed'
fi
[ -f "$pending" ] && [ ! -L "$pending" ] || fail 'download is not a regular file'
expected=64d73d8b9e8e584643432c4c43940cd08ce5af34a091239e8e3da3c4783da47f
if command -v sha256sum >/dev/null 2>&1; then
  checksum=$(sha256sum "$pending") || fail 'checksum calculation failed'
elif command -v shasum >/dev/null 2>&1; then
  checksum=$(shasum -a 256 "$pending") || fail 'checksum calculation failed'
else
  fail 'required SHA-256 command not found (install sha256sum or shasum)'
fi
[ "${checksum%% *}" = "$expected" ] || fail 'download checksum mismatch'
chmod 755 "$pending"
mv -f "$pending" "$destination"
trap - EXIT HUP INT TERM
printf 'Installed rbw-env to %s\n' "$destination"
case :$PATH: in
  *:"$install_dir":*) ;;
  *) printf 'Add %s to PATH (the installer did not modify your shell profile).\n' "$install_dir" ;;
esac
