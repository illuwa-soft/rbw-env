#!/usr/bin/env bash
set -eu

ROOT=$(cd "$(dirname "$0")" && pwd)
TMP=${TMPDIR:-/tmp}/rbw-env-test.$$
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin" "$TMP/no-jq" "$TMP/no-pinentry"
REAL_JQ=$(command -v jq)
export REAL_JQ RBW_LOG="$TMP/rbw.log"

cat >"$TMP/bin/jq" <<'SH'
#!/bin/bash
exec "$REAL_JQ" "$@"
SH
cat >"$TMP/bin/pinentry" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$TMP/bin/show-env" <<'SH'
#!/bin/bash
printf 'TOKEN=%s\nargc=%s\n' "$API_TOKEN" "$#"
for arg in "$@"; do printf '<%s>\n' "$arg"; done
SH
cat >"$TMP/bin/rbw" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$RBW_LOG"
case "$1" in
  unlocked) [ "${RBW_CASE:-ok}" != locked ] ;;
  config) printf '%s\n' '{"pinentry":"pinentry"}' ;;
  list)
    case "${RBW_CASE:-ok}" in
      malformed) printf '%s\n' 'not-json' ;;
      invalid) printf '%s\n' '[{"id":"1","name":"bad-name","folder":"target","type":"SecureNote"}]' ;;
      emptykey) printf '%s\n' '[{"id":"1","name":"","folder":"target","type":"SecureNote"}]' ;;
      duplicate) printf '%s\n' '[{"id":"1","name":"API_TOKEN","folder":"target","type":"SecureNote"},{"id":"2","name":"API_TOKEN","folder":"target","type":"SecureNote"}]' ;;
      empty) printf '%s\n' '[{"id":"3","name":"EMPTY","folder":"target","type":"SecureNote"}]' ;;
      *) printf '%s\n' '[{"id":"1","name":"API_TOKEN","folder":"target","type":"SecureNote"},{"id":"2","name":"CHILD","folder":"target/child","type":"SecureNote"},{"id":"9","name":"OTHER","folder":"other","type":"SecureNote"}]' ;;
    esac ;;
  get)
    case "${RBW_CASE:-ok}:$2" in
      empty:3) printf '%s\n' '{"id":"3","folder":"target","name":"EMPTY","data":"SecureNote","fields":[],"notes":"\nignored"}' ;;
      *:1) printf '%s\n' '{"id":"1","folder":"target","name":"API_TOKEN","data":"SecureNote","fields":[],"notes":"fake-value\nhuman memo SECRET_MEMO_SENTINEL"}' ;;
      *) printf '%s\n' '{"id":"9","folder":"other","name":"OTHER","data":"SecureNote","fields":[],"notes":"SHOULD_NOT_APPEAR"}' ;;
    esac ;;
  *) exit 2 ;;
esac
SH
chmod +x "$TMP/bin/"*
cp "$TMP/bin/rbw" "$TMP/no-jq/rbw"
cp "$TMP/bin/rbw" "$TMP/no-pinentry/rbw"
cp "$TMP/bin/jq" "$TMP/no-pinentry/jq"

pass=0
fail() { printf 'not ok - %s\n' "$1"; exit 1; }
check() { name=$1; shift; "$@" || fail "$name"; pass=$((pass + 1)); printf 'ok %s - %s\n' "$pass" "$name"; }
run() { out=$1; err=$2; shift 2; PATH="$TMP/bin" /bin/bash "$ROOT/rbw-env" "$@" >"$out" 2>"$err"; }
equals() { [ "$(cat "$1")" = "$2" ]; }
contains() { case $(cat "$1") in *"$2"*) return 0;; *) return 1;; esac; }
not_contains() { ! contains "$1" "$2"; }

: >"$RBW_LOG"
run "$TMP/out" "$TMP/err" target || fail dotenv
check "dotenv mode and first Notes line only" equals "$TMP/out" 'API_TOKEN=fake-value'
check "exact folder only" not_contains "$TMP/out" SHOULD_NOT_APPEAR
check "rbw list is raw and unscoped for exact local filtering" contains "$RBW_LOG" 'list --raw'

# shellcheck disable=SC2016 # Literal argv verifies that no shell expansion occurs.
run "$TMP/out" "$TMP/err" target -- show-env 'two words' 'literal;$HOME' || fail inline
check "inline exec preserves environment and exact argv" equals "$TMP/out" $'TOKEN=fake-value\nargc=2\n<two words>\n<literal;$HOME>'

if PATH="$TMP/no-jq" /bin/bash "$ROOT/rbw-env" target >"$TMP/out" 2>"$TMP/err"; then fail "missing jq accepted"; fi
check "missing dependency is rejected" contains "$TMP/err" 'required command not found: jq'
rm "$TMP/no-jq/rbw"
if PATH="$TMP/no-jq" /bin/bash "$ROOT/rbw-env" target >"$TMP/out" 2>"$TMP/err"; then fail "missing rbw accepted"; fi
check "missing rbw is rejected" contains "$TMP/err" 'required command not found: rbw'
cp "$TMP/bin/rbw" "$TMP/no-jq/rbw"
if PATH="$TMP/no-pinentry" /bin/bash "$ROOT/rbw-env" target >"$TMP/out" 2>"$TMP/err"; then fail "missing pinentry accepted"; fi
check "missing pinentry is rejected" contains "$TMP/err" 'usable pinentry'

if RBW_CASE=locked run "$TMP/out" "$TMP/err" target; then fail "locked vault accepted"; fi
check "locked vault instructs explicit unlock" contains "$TMP/err" 'rbw unlock'

for case_name in invalid emptykey duplicate empty malformed; do
  if RBW_CASE=$case_name run "$TMP/out" "$TMP/err" target; then fail "$case_name accepted"; fi
  check "$case_name input fails without value leakage" not_contains "$TMP/err" 'fake-value'
done
check "memo content never leaks on errors" not_contains "$TMP/err" SECRET_MEMO_SENTINEL

if run "$TMP/out" "$TMP/err" target --; then fail "missing command accepted"; fi
check "command omission after -- is rejected" contains "$TMP/err" 'command required after --'

printf '1..%s\n' "$pass"
