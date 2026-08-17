#!/usr/bin/env bash
set -eu

fail() { printf 'rbw-env installer: %s\n' "$1" >&2; exit 1; }
for dependency in curl rbw jq; do
  command -v "$dependency" >/dev/null 2>&1 || fail "required command not found: $dependency"
done

rbw=$(command -v rbw)
jq=$(command -v jq)
pinentry=''
configured=$("$rbw" config show 2>/dev/null | "$jq" -er '.pinentry | strings | select(length > 0)' 2>/dev/null || :)
if [ -n "$configured" ]; then
  if case "$configured" in */*) [ -x "$configured" ];; *) command -v "$configured" >/dev/null 2>&1;; esac; then
    pinentry=$configured
  fi
fi
if [ -z "$pinentry" ]; then
  for candidate in pinentry pinentry-curses pinentry-tty pinentry-mac; do
    if command -v "$candidate" >/dev/null 2>&1; then pinentry=$candidate; break; fi
  done
fi
[ -n "$pinentry" ] || fail 'no usable pinentry found (configure rbw pinentry or install one)'

install_dir=${RBW_ENV_INSTALL_DIR:-"$HOME/.local/bin"}
version=${RBW_ENV_VERSION:-v0.1.0}
destination=$install_dir/rbw-env
pending=$destination.new.$$
trap 'rm -f "$pending"' EXIT HUP INT TERM
mkdir -p "$install_dir"
if ! curl -fsSL "https://raw.githubusercontent.com/illuwa-soft/rbw-env/$version/rbw-env" -o "$pending"; then
  fail 'download failed'
fi
chmod 755 "$pending"
mv -f "$pending" "$destination"
trap - EXIT HUP INT TERM
printf 'Installed rbw-env to %s\n' "$destination"
case :$PATH: in
  *:"$install_dir":*) ;;
  *) printf 'Add %s to PATH (the installer did not modify your shell profile).\n' "$install_dir" ;;
esac
