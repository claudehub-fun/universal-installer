#!/usr/bin/env bash
# Tests for install.sh pure functions. Run: bash test_install.sh
set -euo pipefail

PASS=0; FAIL=0

assert_eq() {
  local desc="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    echo "  PASS: $desc"; PASS=$((PASS+1))
  else
    echo "  FAIL: $desc — got='$got' want='$want'"; FAIL=$((FAIL+1))
  fi
}

# ── load pure functions without executing main ────────────────────────────────
API_KEY="test-key"
_script="$(dirname "$0")/install.sh"
_tmp_src="$(mktemp)"
grep -v '^main "\$@"' "$_script" > "$_tmp_src"
# shellcheck disable=SC1090
source "$_tmp_src"
rm -f "$_tmp_src"

echo "=== slugify ==="
assert_eq "lowercase"           "$(slugify 'Hello World')"  "helloworld"
assert_eq "strip special chars" "$(slugify 'Foo-Bar_99!')"  "foobar99"
assert_eq "empty → custom"      "$(slugify '')"             "custom"
assert_eq "all non-alnum"       "$(slugify '!@#$%')"        "custom"
assert_eq "already clean"       "$(slugify 'myprovider')"   "myprovider"

echo "=== shell_rc_file ==="
orig_shell="${SHELL:-}"
SHELL=/bin/zsh;  assert_eq "zsh"       "$(shell_rc_file)" "$HOME/.zshrc"
SHELL=/bin/bash; assert_eq "bash"      "$(shell_rc_file)" "$HOME/.bashrc"
SHELL=/bin/sh;   assert_eq "sh→bashrc" "$(shell_rc_file)" "$HOME/.bashrc"
SHELL="";        assert_eq "empty"     "$(shell_rc_file)" "$HOME/.bashrc"
SHELL="$orig_shell"

echo "=== vscode_user_settings_path ==="
case "$(uname -s)" in
  Darwin) assert_eq "darwin path" "$(vscode_user_settings_path)" \
            "$HOME/Library/Application Support/Code/User/settings.json" ;;
  Linux)  assert_eq "linux path"  "$(vscode_user_settings_path)" \
            "$HOME/.config/Code/User/settings.json" ;;
  *)      echo "  SKIP: vscode path (unknown OS)" ;;
esac

echo "=== require_config ==="
API_KEY="sk-live-123"
require_config
assert_eq "valid config passes" "$?" "0"

export INSTALLER_TTY=/dev/null
API_KEY=""
out=$(require_config 2>&1) && rc=0 || rc=$?
assert_eq "empty API_KEY prompts and fails" "$rc" "1"
unset INSTALLER_TTY

echo "=== set_json_value ==="
tmp="$(mktemp)"
# On Windows/Git Bash, python3 needs a native Windows path; cygpath converts it.
tmp_py="$tmp"
command -v cygpath >/dev/null 2>&1 && tmp_py="$(cygpath -m "$tmp")"
trap 'rm -f "$tmp"' EXIT

set_json_value "$tmp" "a.b.c" "hello"
val="$(python3 -c "import json; d=json.load(open(r'$tmp_py')); print(d['a']['b']['c'])")"
assert_eq "nested write" "$val" "hello"

set_json_value "$tmp" "a.b.d" "world"
val="$(python3 -c "import json; d=json.load(open(r'$tmp_py')); print(d['a']['b']['c'], d['a']['b']['d'])")"
assert_eq "sibling key preserved" "$val" "hello world"

set_json_value "$tmp" "a.b.c" "updated"
val="$(python3 -c "import json; d=json.load(open(r'$tmp_py')); print(d['a']['b']['c'])")"
assert_eq "overwrite existing" "$val" "updated"

# ── summary ─────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
