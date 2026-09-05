#!/usr/bin/env bash
set -eu

ROOT=$(cd "$(dirname "$0")" && pwd)
TMP=${TMPDIR:-/tmp}/rbw-env-test.$$
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin" "$TMP/no-jq" "$TMP/no-jq-install" "$TMP/no-pinentry" "$TMP/with-deps" "$TMP/home" "$TMP/install"
mkdir -p "$TMP/home/.local/bin"
REAL_JQ=$(command -v jq)
PYTHON3=$(command -v python3)
export REAL_JQ RBW_LOG="$TMP/rbw.log" RBW_DOWNLOAD_SOURCE="$ROOT/rbw-env" RBW_CURL_LOG="$TMP/curl.log" PACKAGE_LOG="$TMP/package.log"

cat >"$TMP/bin/jq" <<'SH'
#!/bin/bash
exec "$REAL_JQ" "$@"
SH
cat >"$TMP/bin/pinentry" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$TMP/bin/curl" <<'SH'
#!/bin/bash
[ "$#" -eq 4 ] && [ "$1" = -fsSL ] && [ "$3" = -o ] || exit 2
printf '%s\n%s\n%s\n' "$2" "$4" "$(umask)" >>"$RBW_CURL_LOG"
[ "$2" = 'https://raw.githubusercontent.com/illuwa-soft/rbw-env/v0.2.0/rbw-env' ] || exit 22
case "${RBW_CURL_CASE:-ok}" in
  corrupt) printf '%s\n' SECRET_CORRUPT_DOWNLOAD >"$4" ;;
  symlink) rm -f "$4"; ln -s "$RBW_DOWNLOAD_SOURCE" "$4" ;;
  *) cp "$RBW_DOWNLOAD_SOURCE" "$4" ;;
esac
SH
cat >"$TMP/bin/sha256sum" <<'SH'
#!/bin/bash
[ "$#" -eq 1 ] || exit 2
if cmp -s "$1" "$RBW_DOWNLOAD_SOURCE"; then
  printf '0fcf997b749ee7a637356eb8c50bff7825c1a8a9ce504aa3246cdaa08a070495  %s\n' "$1"
else
  printf 'mismatch  %s\n' "$1"
fi
SH
cat >"$TMP/bin/show-env" <<'SH'
#!/bin/bash
printf 'TOKEN=%s\nargc=%s\n' "$API_TOKEN" "$#"
for arg in "$@"; do printf '<%s>\n' "$arg"; done
SH
cat >"$TMP/hermes-parser.py" <<'PY'
import os
import sys

from agent.secret_sources.command import parse_secret_output

with open(sys.argv[1], encoding="utf-8") as stream:
    actual = parse_secret_output(stream.read(), "API_TOKEN")
assert actual == os.environ["EXPECTED"], (actual, os.environ["EXPECTED"])
PY
cat >"$TMP/pty-run.py" <<'PY'
import os
import pty
import subprocess
import sys

master, slave = pty.openpty()
with open(sys.argv[1], "wb") as stdout, open(sys.argv[2], "wb") as stderr:
    result = subprocess.run(sys.argv[3:], stdin=slave, stdout=stdout, stderr=stderr)
os.close(slave)
os.close(master)
sys.exit(result.returncode)
PY
cat >"$TMP/bin/rbw" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$RBW_LOG"
case "$1" in
  unlocked)
    case "${RBW_CASE:-ok}" in
      locked|unlock_fail|recheck_fail) exit 1 ;;
      interactive) [ -f "$RBW_STATE" ] ;;
    esac ;;
  unlock)
    printf '%s\n' SECRET_UNLOCK_STDOUT_SENTINEL
    printf '%s\n' SECRET_UNLOCK_STDERR_SENTINEL >&2
    case "${RBW_CASE:-ok}" in
      interactive) : >"$RBW_STATE" ;;
      unlock_fail) exit 1 ;;
      recheck_fail) : ;;
      *) exit 2 ;;
    esac ;;
  config) "$REAL_JQ" -cn --arg pinentry "${RBW_CONFIG_PINENTRY-pinentry}" '{pinentry:$pinentry}' ;;
  list)
    case "${RBW_CASE:-ok}" in
      malformed) printf '%s\n' 'not-json' ;;
      list_ok) printf '%s\n' '[{"id":"7","name":"Z_KEY","folder":"team/PROD","type":"Note"},{"id":"8","name":"ignored-name","folder":"team/PROD","type":"Note"},{"id":"9","name":"A_KEY","folder":"alpha","type":"Note"},{"id":"10","name":"LOGIN","folder":"team/PROD","type":"Login"},{"id":"11","name":"NULL_FOLDER","folder":null,"type":"Note"},{"id":"12","name":"PROD","folder":"team","type":"Note"},{"id":"13","name":"ROOT","folder":"zeta","type":"Note"}]' ;;
      list_empty_component) printf '%s\n' '[{"id":"14","name":"ONE","folder":"/team","type":"Note"},{"id":"15","name":"TWO","folder":"team/","type":"Note"},{"id":"16","name":"THREE","folder":"team//prod","type":"Note"}]' ;;
      list_duplicate) printf '%s\n' '[{"id":"12","name":"API_TOKEN","folder":"team/prod","type":"Note"},{"id":"13","name":"API_TOKEN","folder":"team/prod","type":"Note"}]' ;;
      list_duplicate_id) printf '%s\n' '[{"id":"12","name":"API_TOKEN","folder":"team/prod","type":"Note"},{"id":"12","name":"OTHER_KEY","folder":"other","type":"Note"}]' ;;
      list_malformed) printf '%s\n' '[{"id":"14","name":"SECRET_LIST_METADATA_SENTINEL","folder":"team/prod"}]' ;;
      multi_list) printf '%s\n%s\n' '[{"id":"21","name":"API_TOKEN","folder":"team/prod","type":"Note"}]' '[{"id":"21","name":"API_TOKEN","folder":"team/prod","type":"Note"}]' ;;
      folder_multi_list) printf '%s\n%s\n' '[{"id":"1","name":"API_TOKEN","folder":"target","type":"Note"}]' '[{"id":"1","name":"API_TOKEN","folder":"target","type":"Note"}]' ;;
      folder_multi_detail) printf '%s\n' '[{"id":"1","name":"API_TOKEN","folder":"target","type":"Note"}]' ;;
      multi_detail|reserved_*)
        case "${RBW_CASE}" in
          reserved_list) folder=list; id=31 ;;
          reserved_show) folder=show; id=32 ;;
          *) folder=team/prod; id=21 ;;
        esac
        "$REAL_JQ" -cn --arg id "$id" --arg folder "$folder" '[{id:$id,name:"API_TOKEN",folder:$folder,type:"Note"}]'
        ;;
      show_ambiguous) printf '%s\n' '[{"id":"21","name":"API_TOKEN","folder":"team/prod","type":"Note"},{"id":"22","name":"API_TOKEN","folder":"team/prod","type":"Note"}]' ;;
      show_missing) printf '%s\n' '[{"id":"23","name":"OTHER","folder":"team/prod","type":"Note"}]' ;;
      show_wrong_type) printf '%s\n' '[{"id":"21","name":"API_TOKEN","folder":"team/prod","type":"Login"}]' ;;
      show_*) printf '%s\n' '[{"id":"21","name":"API_TOKEN","folder":"team/prod","type":"Note"}]' ;;
      invalid) printf '%s\n' '[{"id":"1","name":"bad-name","folder":"target","type":"Note"}]' ;;
      emptykey) printf '%s\n' '[{"id":"1","name":"","folder":"target","type":"Note"}]' ;;
      duplicate) printf '%s\n' '[{"id":"1","name":"API_TOKEN","folder":"target","type":"Note"},{"id":"2","name":"API_TOKEN","folder":"target","type":"Note"}]' ;;
      empty) printf '%s\n' '[{"id":"3","name":"EMPTY","folder":"target","type":"Note"}]' ;;
      nul) printf '%s\n' '[{"id":"4","name":"NUL_VALUE","folder":"target","type":"Note"}]' ;;
      *) printf '%s\n' '[{"id":"1","name":"API_TOKEN","folder":"target","type":"Note"},{"id":"2","name":"CHILD","folder":"target/child","type":"Note"},{"id":"9","name":"OTHER","folder":"other","type":"Note"}]' ;;
    esac ;;
  get)
    case "${RBW_CASE:-ok}:$2" in
      empty:3) printf '%s\n' '{"id":"3","folder":"target","name":"EMPTY","data":null,"fields":[],"notes":"\nignored"}' ;;
      nul:4) printf '%s\n' '{"id":"4","folder":"target","name":"NUL_VALUE","data":null,"fields":[],"notes":"before\u0000after\nignored"}' ;;
      data_nonnull:1) printf '%s\n' '{"id":"1","folder":"target","name":"API_TOKEN","data":"SecureNote","fields":[],"notes":"fake-value\nhuman memo SECRET_MEMO_SENTINEL"}' ;;
      data_missing:1) printf '%s\n' '{"id":"1","folder":"target","name":"API_TOKEN","fields":[],"notes":"fake-value\nhuman memo SECRET_MEMO_SENTINEL"}' ;;
      show_id_mismatch:21) printf '%s\n' '{"id":"wrong","folder":"team/prod","name":"API_TOKEN","data":null,"notes":"show-value\nSECRET_SHOW_MEMO_SENTINEL"}' ;;
      show_folder_mismatch:21) printf '%s\n' '{"id":"21","folder":"other","name":"API_TOKEN","data":null,"notes":"show-value\nSECRET_SHOW_MEMO_SENTINEL"}' ;;
      show_name_mismatch:21) printf '%s\n' '{"id":"21","folder":"team/prod","name":"OTHER","data":null,"notes":"show-value\nSECRET_SHOW_MEMO_SENTINEL"}' ;;
      show_data_nonnull:21) printf '%s\n' '{"id":"21","folder":"team/prod","name":"API_TOKEN","data":"SecureNote","notes":"show-value\nSECRET_SHOW_MEMO_SENTINEL"}' ;;
      show_data_missing:21) printf '%s\n' '{"id":"21","folder":"team/prod","name":"API_TOKEN","notes":"show-value\nSECRET_SHOW_MEMO_SENTINEL"}' ;;
      show_notes_wrong:21) printf '%s\n' '{"id":"21","folder":"team/prod","name":"API_TOKEN","data":null,"notes":["show-value"]}' ;;
      show_empty:21) printf '%s\n' '{"id":"21","folder":"team/prod","name":"API_TOKEN","data":null,"notes":"\nSECRET_SHOW_MEMO_SENTINEL"}' ;;
      show_nul:21) printf '%s\n' '{"id":"21","folder":"team/prod","name":"API_TOKEN","data":null,"notes":"before\u0000after\nSECRET_SHOW_MEMO_SENTINEL"}' ;;
      show_*:21) "$REAL_JQ" -cn --arg notes "${RBW_VALUE:-show-value}"$'\nSECRET_SHOW_MEMO_SENTINEL' \
        '{id:"21",folder:"team/prod",name:"API_TOKEN",data:null,notes:$notes}' ;;
      multi_detail:21) printf '%s\n%s\n' \
        '{"id":"21","folder":"team/prod","name":"API_TOKEN","data":null,"notes":"show-value"}' \
        '{"id":"21","folder":"team/prod","name":"API_TOKEN","data":null,"notes":"show-value"}' ;;
      reserved_list:31) printf '%s\n' '{"id":"31","folder":"list","name":"API_TOKEN","data":null,"notes":"fake-value"}' ;;
      reserved_show:32) printf '%s\n' '{"id":"32","folder":"show","name":"API_TOKEN","data":null,"notes":"fake-value"}' ;;
      folder_multi_detail:1) printf '%s\n%s\n' \
        '{"id":"1","folder":"target","name":"API_TOKEN","data":null,"notes":"fake-value"}' \
        '{"id":"1","folder":"target","name":"API_TOKEN","data":null,"notes":"fake-value"}' ;;
      *:1) "$REAL_JQ" -cn --arg notes "${RBW_VALUE:-fake-value}"$'\nhuman memo SECRET_MEMO_SENTINEL' \
        '{id:"1",folder:"target",name:"API_TOKEN",data:null,fields:[],notes:$notes}' ;;
      *) printf '%s\n' '{"id":"9","folder":"other","name":"OTHER","data":null,"fields":[],"notes":"SHOULD_NOT_APPEAR"}' ;;
    esac ;;
  *) exit 2 ;;
esac
SH
chmod +x "$TMP/bin/"*
cp "$TMP/bin/rbw" "$TMP/no-jq/rbw"
cp "$TMP/bin/rbw" "$TMP/bin/curl" "$TMP/no-jq-install/"
for command in brew apt-get apt yum dnf pacman sudo; do
  cat >"$TMP/no-jq-install/$command" <<'SH'
#!/bin/bash
printf '%s\n' "$0 $*" >>"$PACKAGE_LOG"
exit 99
SH
done
chmod +x "$TMP/no-jq-install/"*
cp "$TMP/bin/rbw" "$TMP/no-pinentry/rbw"
cp "$TMP/bin/jq" "$TMP/no-pinentry/jq"
cp "$TMP/bin/jq" "$TMP/with-deps/jq"
cp "$TMP/bin/pinentry" "$TMP/with-deps/pinentry"
cp "$TMP/bin/rbw" "$TMP/home/.local/bin/rbw"

pass=0
fail() { printf 'not ok - %s\n' "$1"; exit 1; }
check() { name=$1; shift; "$@" || fail "$name"; pass=$((pass + 1)); printf 'ok %s - %s\n' "$pass" "$name"; }
run() { out=$1; err=$2; shift 2; PATH="$TMP/bin" /bin/bash "$ROOT/rbw-env" "$@" >"$out" 2>"$err"; }
run_tty() { out=$1; err=$2; shift 2; PATH="$TMP/bin" "$PYTHON3" "$TMP/pty-run.py" "$out" "$err" /bin/bash "$ROOT/rbw-env" "$@"; }
run_install() { PATH="$TMP/bin:/usr/bin:/bin:/sbin" HOME="$TMP/home" RBW_ENV_INSTALL_DIR="$TMP/install" /bin/bash "$ROOT/install.sh" >"$TMP/out" 2>"$TMP/err"; }
equals() { [ "$(cat "$1")" = "$2" ]; }
contains() { case $(cat "$1") in *"$2"*) return 0;; *) return 1;; esac; }
not_contains() { ! contains "$1" "$2"; }
count_log() { [ "$(grep -c "^$2$" "$1" || :)" -eq "$3" ]; }
count_prefix_log() { [ "$(grep -c "^$2" "$1" || :)" -eq "$3" ]; }

: >"$RBW_LOG"
run "$TMP/out" "$TMP/err" target || fail dotenv
check "real rbw 1.15 Note-list/null-data detail contract and first Notes line" equals "$TMP/out" "API_TOKEN='fake-value'"
check "exact folder only" not_contains "$TMP/out" SHOULD_NOT_APPEAR
check "rbw list is raw and unscoped for exact local filtering" contains "$RBW_LOG" 'list --raw'

: >"$RBW_LOG"
RBW_CASE=list_ok run "$TMP/out" "$TMP/err" list || fail "list selectors"
check "list prints a deterministic ASCII tree with a path/leaf collision" equals "$TMP/out" $'.\n|-- alpha/\n|   `-- A_KEY\n|-- team/\n|   |-- PROD/\n|   |   `-- Z_KEY\n|   `-- PROD\n`-- zeta/\n    `-- ROOT'
check "list never fetches item details" count_prefix_log "$RBW_LOG" 'get ' 0
if RBW_CASE=list_empty_component run "$TMP/out" "$TMP/err" list; then fail "empty slash-separated component accepted"; fi
check "empty slash-separated components fail generically" equals "$TMP/err" 'rbw-env: list results are malformed or ambiguous'
check "empty slash-separated components emit no stdout" test ! -s "$TMP/out"
check "empty slash-separated components never fetch details" count_prefix_log "$RBW_LOG" 'get ' 0
if RBW_CASE=list_duplicate run "$TMP/out" "$TMP/err" list; then fail "duplicate list selector accepted"; fi
check "duplicate list selector fails with a generic error" equals "$TMP/err" 'rbw-env: list results are malformed or ambiguous'
check "duplicate list selector emits no stdout" test ! -s "$TMP/out"
if RBW_CASE=list_duplicate_id run "$TMP/out" "$TMP/err" list; then fail "duplicate list id accepted"; fi
check "duplicate list id fails with a generic error" equals "$TMP/err" 'rbw-env: list results are malformed or ambiguous'
if RBW_CASE=list_malformed run "$TMP/out" "$TMP/err" list; then fail "malformed list metadata accepted"; fi
check "malformed list metadata fails without leaking metadata" not_contains "$TMP/err" SECRET_LIST_METADATA_SENTINEL
if RBW_CASE=list_ok run "$TMP/out" "$TMP/err" list extra; then fail "list extra argument accepted"; fi
check "list rejects extra arguments without output" test ! -s "$TMP/out"
if RBW_CASE=multi_list run "$TMP/out" "$TMP/err" list; then fail "multiple list documents accepted"; fi
check "list rejects multiple top-level documents without output" test ! -s "$TMP/out"

: >"$RBW_LOG"
RBW_CASE=show_ok run "$TMP/out" "$TMP/err" show team/prod/API_TOKEN || fail "show selector"
check "show prints the raw first Notes line" equals "$TMP/out" 'show-value'
check "show fetches only the resolved item id" count_log "$RBW_LOG" 'get 21 --raw' 1
check "show performs exactly one detail fetch" count_prefix_log "$RBW_LOG" 'get ' 1
# shellcheck disable=SC2016 # Dollar text is literal show output test data.
raw_show_value=' raw $VALUE # = "quotes" '
RBW_CASE=show_ok RBW_VALUE=$raw_show_value run "$TMP/out" "$TMP/err" show team/prod/API_TOKEN || fail "show raw value"
check "show preserves the raw first-line value" equals "$TMP/out" "$raw_show_value"

for show_case in show_ambiguous show_missing show_wrong_type malformed; do
  : >"$RBW_LOG"
  if RBW_CASE=$show_case run "$TMP/out" "$TMP/err" show team/prod/API_TOKEN; then fail "$show_case accepted"; fi
  check "$show_case resolution fails without stdout" test ! -s "$TMP/out"
  check "$show_case resolution never fetches item details" count_prefix_log "$RBW_LOG" 'get ' 0
done
if RBW_CASE=multi_list run "$TMP/out" "$TMP/err" show team/prod/API_TOKEN; then fail "multiple show list documents accepted"; fi
check "show rejects multiple list documents without stdout" test ! -s "$TMP/out"
if RBW_CASE=multi_detail run "$TMP/out" "$TMP/err" show team/prod/API_TOKEN; then fail "multiple detail documents accepted"; fi
check "show rejects multiple detail documents without stdout" test ! -s "$TMP/out"
for show_case in show_id_mismatch show_folder_mismatch show_name_mismatch show_data_nonnull show_data_missing show_notes_wrong show_empty show_nul; do
  if RBW_CASE=$show_case run "$TMP/out" "$TMP/err" show team/prod/API_TOKEN; then fail "$show_case accepted"; fi
  check "$show_case detail fails without stdout" test ! -s "$TMP/out"
  check "$show_case detail error does not leak values" not_contains "$TMP/err" show-value
  check "$show_case detail error does not leak memo content" not_contains "$TMP/err" SECRET_SHOW_MEMO_SENTINEL
done
for bad_selector in API_TOKEN /API_TOKEN team/prod/ team/prod/bad-key; do
  if RBW_CASE=show_ok run "$TMP/out" "$TMP/err" show "$bad_selector"; then fail "invalid show selector accepted"; fi
  check "invalid show selector fails without stdout" test ! -s "$TMP/out"
done
if RBW_CASE=show_ok run "$TMP/out" "$TMP/err" show; then fail "missing show selector accepted"; fi
check "show requires one selector" test ! -s "$TMP/out"
if RBW_CASE=show_ok run "$TMP/out" "$TMP/err" show team/prod/API_TOKEN extra; then fail "show extra argument accepted"; fi
check "show rejects extra arguments" test ! -s "$TMP/out"

RBW_CASE=reserved_list run "$TMP/out" "$TMP/err" --folder list || fail "reserved list folder escape"
check "reserved list folder remains available explicitly" equals "$TMP/out" "API_TOKEN='fake-value'"
RBW_CASE=reserved_show run "$TMP/out" "$TMP/err" --folder show -- show-env || fail "reserved show folder escape"
check "reserved show folder preserves command mode" equals "$TMP/out" $'TOKEN=fake-value\nargc=0'

for folder_case in folder_multi_list folder_multi_detail; do
  if RBW_CASE=$folder_case run "$TMP/out" "$TMP/err" target; then fail "$folder_case accepted in folder output mode"; fi
  check "$folder_case folder output fails without stdout" test ! -s "$TMP/out"
  if RBW_CASE=$folder_case run "$TMP/out" "$TMP/err" target -- show-env; then fail "$folder_case accepted in folder command mode"; fi
  check "$folder_case folder command fails before exec" test ! -s "$TMP/out"
  check "$folder_case folder errors do not leak values" not_contains "$TMP/err" fake-value
done

run_home_bin() { HOME="$TMP/home" PATH="$TMP/with-deps" BASH_ENV='' ENV='' REAL_JQ="$REAL_JQ" /bin/bash "$ROOT/rbw-env" target >"$TMP/out" 2>"$TMP/err"; equals "$TMP/out" "API_TOKEN='fake-value'"; }
check "rbw resolves from conventional HOME user bin when PATH omits it" run_home_bin

HERMES_PYTHON=${HERMES_PYTHON:-}
if [ -z "$HERMES_PYTHON" ]; then
  hermes_bin=$(command -v hermes || :)
  [ -n "$hermes_bin" ] && HERMES_PYTHON=${hermes_bin%/*}/python
fi
[ -x "$HERMES_PYTHON" ] || fail "installed Hermes Python not found"
# shellcheck disable=SC2016 # Dollar expressions are literal parser test data.
for value in ' leading' 'trailing ' ' before #' 'attached#' 'a"b' "a'b" '"matching"' "'matching'" 'a\b' '$BARE' '${BRACED}' 'a=b'; do
  RBW_VALUE=$value run "$TMP/out" "$TMP/err" target || fail "Hermes value output"
  EXPECTED=$value "$HERMES_PYTHON" "$TMP/hermes-parser.py" "$TMP/out" || fail "Hermes parser round trip"
done
check "supported values round-trip through installed Hermes parser" true

# shellcheck disable=SC2016 # Literal argv verifies that no shell expansion occurs.
run "$TMP/out" "$TMP/err" target -- show-env 'two words' 'literal;$HOME' || fail inline
check "inline exec preserves environment and exact argv" equals "$TMP/out" $'TOKEN=fake-value\nargc=2\n<two words>\n<literal;$HOME>'
inline_value=$' raw \'value\' # \\$HOME=a=b '
RBW_VALUE=$inline_value run "$TMP/out" "$TMP/err" target -- show-env || fail "inline raw value"
inline_expected="TOKEN=$inline_value"$'\nargc=0'
check "inline exec preserves exact raw first-line value" equals "$TMP/out" "$inline_expected"

if PATH="$TMP/no-jq" /bin/bash "$ROOT/rbw-env" target >"$TMP/out" 2>"$TMP/err"; then fail "missing jq accepted"; fi
check "runtime missing jq gives actionable install-and-retry guidance" contains "$TMP/err" 'install jq with your system package manager'
check "runtime missing jq guidance names a macOS command" contains "$TMP/err" 'brew install jq'
: >"$PACKAGE_LOG"
if PATH="$TMP/no-jq-install" HOME="$TMP/home" RBW_ENV_INSTALL_DIR="$TMP/install" /bin/bash "$ROOT/install.sh" >"$TMP/out" 2>"$TMP/err"; then fail "installer missing jq accepted"; fi
check "installer missing jq gives actionable install-and-retry guidance" contains "$TMP/err" 'install jq with your system package manager'
check "installer missing jq guidance names a macOS command" contains "$TMP/err" 'brew install jq'
check "missing jq never invokes a package manager or sudo" test ! -s "$PACKAGE_LOG"
rm "$TMP/no-jq/rbw"
if PATH="$TMP/no-jq" /bin/bash "$ROOT/rbw-env" target >"$TMP/out" 2>"$TMP/err"; then fail "missing rbw accepted"; fi
check "missing rbw is rejected" contains "$TMP/err" 'required command not found: rbw'
cp "$TMP/bin/rbw" "$TMP/no-jq/rbw"
if RBW_CONFIG_PINENTRY='' PATH="$TMP/no-pinentry" /bin/bash "$ROOT/rbw-env" target >"$TMP/out" 2>"$TMP/err"; then fail "missing pinentry accepted"; fi
check "missing pinentry is rejected" contains "$TMP/err" 'usable pinentry'
if RBW_CONFIG_PINENTRY=/missing/SECRET_PINENTRY_SENTINEL run "$TMP/out" "$TMP/err" target; then
  fail "unusable configured pinentry accepted via unrelated PATH candidate"
fi
check "configured pinentry mismatch is rejected" contains "$TMP/err" 'configured rbw pinentry is unusable'
check "configured pinentry value does not leak" not_contains "$TMP/err" SECRET_PINENTRY_SENTINEL

: >"$RBW_LOG"
if RBW_CASE=locked run "$TMP/out" "$TMP/err" target; then fail "noninteractive locked vault accepted"; fi
# shellcheck disable=SC2016 # Backticks are literal expected guidance.
check "noninteractive locked vault instructs explicit manual unlock" contains "$TMP/err" 'run `rbw unlock` interactively'
check "noninteractive locked vault never attempts unlock" count_log "$RBW_LOG" unlock 0

rm -f "$TMP/rbw.state"
: >"$RBW_LOG"
if ! RBW_CASE=interactive RBW_STATE="$TMP/rbw.state" run_tty "$TMP/out" "$TMP/err" target; then
  fail "interactive locked vault did not unlock"
fi
check "interactive locked vault emits dotenv after unlocking" equals "$TMP/out" "API_TOKEN='fake-value'"
check "interactive locked vault attempts exact unlock once" count_log "$RBW_LOG" unlock 1
check "interactive locked vault checks unlocked state twice" count_log "$RBW_LOG" unlocked 2
check "interactive unlock output is suppressed" not_contains "$TMP/out" SECRET_UNLOCK_
check "interactive unlock errors are value-free" not_contains "$TMP/err" SECRET_UNLOCK_

for unlock_case in unlock_fail recheck_fail; do
  : >"$RBW_LOG"
  if RBW_CASE=$unlock_case run_tty "$TMP/out" "$TMP/err" target; then fail "$unlock_case accepted"; fi
  case $unlock_case in
    unlock_fail) expected_checks=1; expected_error='interactive rbw unlock failed' ;;
    recheck_fail) expected_checks=2; expected_error='rbw remains locked after interactive unlock' ;;
  esac
  check "$unlock_case attempts exact unlock once" count_log "$RBW_LOG" unlock 1
  check "$unlock_case has exact unlocked check count" count_log "$RBW_LOG" unlocked "$expected_checks"
  check "$unlock_case reports a generic failure" contains "$TMP/err" "$expected_error"
  check "$unlock_case failure is value-free" not_contains "$TMP/err" SECRET_UNLOCK_
  check "$unlock_case emits no secret output" test ! -s "$TMP/out"
done

for case_name in invalid emptykey duplicate empty nul malformed data_nonnull data_missing; do
  if RBW_CASE=$case_name run "$TMP/out" "$TMP/err" target; then fail "$case_name accepted"; fi
  check "$case_name input fails without value leakage" not_contains "$TMP/err" 'fake-value'
done
check "memo content never leaks on errors" not_contains "$TMP/err" SECRET_MEMO_SENTINEL

if run "$TMP/out" "$TMP/err" target --; then fail "missing command accepted"; fi
check "command omission after -- is rejected" contains "$TMP/err" 'command required after --'

: >"$RBW_CURL_LOG"
RBW_ENV_VERSION=main run_install || fail "fixed installer ref"
check "installer ignores mutable ref override and uses v0.2.0" contains "$RBW_CURL_LOG" '/v0.2.0/rbw-env'
check "installer writes exact checked helper bytes" equals "$TMP/install/rbw-env" "$(cat "$ROOT/rbw-env")"
cp "$TMP/install/rbw-env" "$TMP/installed-before-failure"
if RBW_CURL_CASE=corrupt run_install; then fail "checksum mismatch accepted"; fi
check "checksum mismatch preserves installed helper" equals "$TMP/install/rbw-env" "$(cat "$TMP/installed-before-failure")"
check "checksum failure does not leak downloaded bytes" not_contains "$TMP/err" SECRET_CORRUPT_DOWNLOAD
: >"$RBW_CURL_LOG"
run_install || fail "safe staging install"
staging=''
staging_umask=''
line_number=0
while IFS= read -r line; do
  line_number=$((line_number + 1))
  [ "$line_number" -eq 2 ] && staging=$line
  [ "$line_number" -eq 3 ] && staging_umask=$line
done <"$RBW_CURL_LOG"
case $staging in "$TMP/install/.rbw-env."??????) :;; *) fail "installer staging is not mktemp-generated in install directory";; esac
check "installer uses private staging umask" test "$staging_umask" = 0077
if RBW_CURL_CASE=symlink run_install; then fail "symlink download accepted"; fi
check "non-regular download preserves installed helper" equals "$TMP/install/rbw-env" "$(cat "$TMP/installed-before-failure")"
check "temporary staging files are cleaned" test ! -e "$staging"
if RBW_CONFIG_PINENTRY=/missing/SECRET_INSTALLER_PINENTRY run_install; then
  fail "installer accepted unusable configured pinentry via unrelated PATH candidate"
fi
check "installer rejects configured pinentry mismatch" contains "$TMP/err" 'configured rbw pinentry is unusable'
check "installer pinentry error is value-free" not_contains "$TMP/err" SECRET_INSTALLER_PINENTRY

printf '1..%s\n' "$pass"
