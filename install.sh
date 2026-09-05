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
completion_dir=${RBW_ENV_ZSH_COMPLETION_DIR:-"${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions"}
destination=$install_dir/rbw-env
completion_destination=$completion_dir/_rbw-env
pending=''
completion_pending=''
helper_backup=''
completion_backup=''
helper_had=false
completion_had=false
helper_installed=false
completion_installed=false
cleanup_install() {
  if $completion_installed; then
    if $completion_had; then mv -f "$completion_backup" "$completion_destination" || :; else rm -f "$completion_destination"; fi
  fi
  if $helper_installed; then
    if $helper_had; then mv -f "$helper_backup" "$destination" || :; else rm -f "$destination"; fi
  fi
  [ -z "$pending" ] || rm -f "$pending"
  [ -z "$completion_pending" ] || rm -f "$completion_pending"
  [ -z "$helper_backup" ] || rm -f "$helper_backup"
  [ -z "$completion_backup" ] || rm -f "$completion_backup"
}
umask 077
mkdir -p "$install_dir" "$completion_dir"
pending=$(mktemp "$install_dir/.rbw-env.XXXXXX") || fail 'could not create installer staging file'
completion_pending=$(mktemp "$completion_dir/._rbw-env.XXXXXX") || {
  rm -f "$pending"
  fail 'could not create completion staging file'
}
trap cleanup_install EXIT HUP INT TERM
if ! curl -fsSL "https://raw.githubusercontent.com/illuwa-soft/rbw-env/v0.4.0/rbw-env" -o "$pending"; then
  fail 'rbw-env download failed'
fi
if ! curl -fsSL "https://raw.githubusercontent.com/illuwa-soft/rbw-env/v0.4.0/_rbw-env" -o "$completion_pending"; then
  fail 'completion download failed'
fi
[ -f "$pending" ] && [ ! -L "$pending" ] || fail 'rbw-env download is not a regular file'
[ -f "$completion_pending" ] && [ ! -L "$completion_pending" ] || fail 'completion download is not a regular file'
if [ -e "$destination" ] || [ -L "$destination" ]; then
  [ -f "$destination" ] && [ ! -L "$destination" ] || fail 'rbw-env destination is not a regular file'
fi
if [ -e "$completion_destination" ] || [ -L "$completion_destination" ]; then
  [ -f "$completion_destination" ] && [ ! -L "$completion_destination" ] || fail 'completion destination is not a regular file'
fi
expected=7c554d9ac9dd3e1e45959d4eed6a393604ee034913c083e276fe46a1bec7f9f7
completion_expected=6d059409ae6bae741b4efc24297d8967f9ae46200873361a33e6eb5a8535b4a2
if command -v sha256sum >/dev/null 2>&1; then
  checksum=$(sha256sum "$pending") || fail 'rbw-env checksum calculation failed'
  completion_checksum=$(sha256sum "$completion_pending") || fail 'completion checksum calculation failed'
elif command -v shasum >/dev/null 2>&1; then
  checksum=$(shasum -a 256 "$pending") || fail 'rbw-env checksum calculation failed'
  completion_checksum=$(shasum -a 256 "$completion_pending") || fail 'completion checksum calculation failed'
else
  fail 'required SHA-256 command not found (install sha256sum or shasum)'
fi
[ "${checksum%% *}" = "$expected" ] || fail 'rbw-env download checksum mismatch'
[ "${completion_checksum%% *}" = "$completion_expected" ] || fail 'completion download checksum mismatch'
if [ -f "$destination" ]; then
  helper_had=true
  helper_backup=$(mktemp "$install_dir/.rbw-env.backup.XXXXXX") || fail 'could not back up installed rbw-env'
  cp -p "$destination" "$helper_backup" || fail 'could not back up installed rbw-env'
fi
if [ -f "$completion_destination" ]; then
  completion_had=true
  completion_backup=$(mktemp "$completion_dir/._rbw-env.backup.XXXXXX") || fail 'could not back up installed completion'
  cp -p "$completion_destination" "$completion_backup" || fail 'could not back up installed completion'
fi
chmod 755 "$pending"
chmod 644 "$completion_pending"
helper_installed=true
mv -f "$pending" "$destination" || fail 'could not replace installed rbw-env'
pending=''
completion_installed=true
mv -f "$completion_pending" "$completion_destination" || fail 'could not replace installed completion'
completion_pending=''
rm -f "$helper_backup" "$completion_backup"
helper_backup=''
completion_backup=''
helper_installed=false
completion_installed=false
trap - EXIT HUP INT TERM
printf 'Installed rbw-env to %s\n' "$destination"
printf 'Installed zsh completion to %s\n' "$completion_destination"
case :$PATH: in
  *:"$install_dir":*) ;;
  *) printf 'Add %s to PATH (the installer did not modify your shell profile).\n' "$install_dir" ;;
esac
case :${FPATH:-}: in
  *:"$completion_dir":*) ;;
  *) printf 'For zsh, add %s to fpath before running: autoload -Uz compinit && compinit\n' "$completion_dir" ;;
esac
