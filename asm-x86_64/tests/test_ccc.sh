#!/bin/sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CCC="$SCRIPT_DIR/../ccc"

MOCK_DIR=$(mktemp -d)
trap 'rm -rf "$MOCK_DIR"' EXIT
mkdir -p "$MOCK_DIR/home" "$MOCK_DIR/xdg"
export HOME="$MOCK_DIR/home"
export XDG_CONFIG_HOME="$MOCK_DIR/xdg"
export CCC_CONFIG="$MOCK_DIR/missing-config.toml"

cat > "$MOCK_DIR/opencode" << 'MOCK'
#!/bin/sh
if [ "$1" != "run" ]; then
  exit 9
fi
shift
agent=""
if [ "$1" = "--agent" ]; then
  agent="$2"
  shift 2
fi
if [ -n "$agent" ]; then
  printf "opencode run --agent %s %s\n" "$agent" "$1"
else
  printf "opencode run %s\n" "$1"
fi
MOCK
chmod +x "$MOCK_DIR/opencode"

cat > "$MOCK_DIR/claude" << 'MOCK'
#!/bin/sh
printf "claude %s\n" "$1"
MOCK
chmod +x "$MOCK_DIR/claude"

cat > "$MOCK_DIR/codex" << 'MOCK'
#!/bin/sh
printf "codex %s\n" "$1"
MOCK
chmod +x "$MOCK_DIR/codex"

cat > "$MOCK_DIR/roocode" << 'MOCK'
#!/bin/sh
printf "roocode %s\n" "$1"
MOCK
chmod +x "$MOCK_DIR/roocode"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "=== ASM ccc tests ==="

echo "no args..."
out=$("$CCC" 2>&1); rc=$?
if [ "$rc" = 1 ] && echo "$out" | grep -q '<Prompt>'; then
    pass "no args"
else
    fail "no args (rc=$rc, out=$out)"
fi

echo "too many args..."
out=$("$CCC" a b 2>&1); rc=$?
if [ "$rc" = 1 ] && echo "$out" | grep -q '<Prompt>'; then
    pass "too many args"
else
    fail "too many args (rc=$rc, out=$out)"
fi

echo "empty prompt..."
out=$("$CCC" "" 2>&1); rc=$?
if [ "$rc" = 1 ] && echo "$out" | grep -q "empty"; then
    pass "empty prompt"
else
    fail "empty prompt (rc=$rc, out=$out)"
fi

echo "whitespace prompt..."
out=$("$CCC" "   " 2>&1); rc=$?
if [ "$rc" = 1 ] && echo "$out" | grep -q "empty"; then
    pass "whitespace prompt"
else
    fail "whitespace prompt (rc=$rc, out=$out)"
fi

echo "help surface..."
out=$("$CCC" --help 2>&1); rc=$?
if [ "$rc" = 0 ] && echo "$out" | grep -q '\[@name\]' && echo "$out" | grep -q 'codex (c/cx)' && echo "$out" | grep -q 'roocode (rc)' && echo "$out" | grep -q 'claude (cc)' && echo "$out" | grep -q 'selector remapping' && echo "$out" | grep -q 'Runner/thinking/provider CLI slots are not parsed here.'; then
    pass "help surface"
else
    fail "help surface (rc=$rc, out=$out)"
fi

echo "happy path..."
out=$(CCC_REAL_OPENCODE="$MOCK_DIR/opencode" "$CCC" "hello world" 2>&1); rc=$?
if [ "$rc" = 0 ] && [ "$out" = "opencode run hello world" ]; then
    pass "happy path"
else
    fail "happy path (rc=$rc, out=$out)"
fi

for selector in c cx; do
    echo "runner $selector maps to codex..."
    mkdir -p "$MOCK_DIR/xdg_$selector/ccc"
    cat > "$MOCK_DIR/xdg_$selector/ccc/config.toml" << MOCK
[defaults]
runner = "$selector"
MOCK
    out=$(PATH="$MOCK_DIR:$PATH" XDG_CONFIG_HOME="$MOCK_DIR/xdg_$selector" CCC_REAL_OPENCODE="$MOCK_DIR/opencode" "$CCC" "hello world" 2>&1); rc=$?
    if [ "$rc" = 0 ] && [ "$out" = "codex hello world" ]; then
        pass "runner $selector maps to codex"
    else
        fail "runner $selector maps to codex (rc=$rc, out=$out)"
    fi
done

echo "runner cc remains claude..."
mkdir -p "$MOCK_DIR/xdg_cc/ccc"
cat > "$MOCK_DIR/xdg_cc/ccc/config.toml" << 'MOCK'
[defaults]
runner = "cc"
MOCK
out=$(PATH="$MOCK_DIR:$PATH" XDG_CONFIG_HOME="$MOCK_DIR/xdg_cc" CCC_REAL_OPENCODE="$MOCK_DIR/opencode" "$CCC" "hello world" 2>&1); rc=$?
if [ "$rc" = 0 ] && [ "$out" = "claude hello world" ]; then
    pass "runner cc remains claude"
else
    fail "runner cc remains claude (rc=$rc, out=$out)"
fi

echo "@name falls back to agent..."
out=$(PATH="$MOCK_DIR:$PATH" CCC_REAL_OPENCODE="$MOCK_DIR/opencode" "$CCC" "@reviewer" "hello world" 2>&1); rc=$?
if [ "$rc" = 0 ] && [ "$out" = "opencode run --agent reviewer hello world" ]; then
    pass "@name falls back to agent"
else
    fail "@name falls back to agent (rc=$rc, out=$out)"
fi

echo "preset agent..."
mkdir -p "$MOCK_DIR/xdg/ccc"
cat > "$MOCK_DIR/xdg/ccc/config.toml" << 'MOCK'
[aliases.reviewer]
agent = "specialist"
MOCK
out=$(PATH="$MOCK_DIR:$PATH" XDG_CONFIG_HOME="$MOCK_DIR/xdg" CCC_REAL_OPENCODE="$MOCK_DIR/opencode" "$CCC" "@reviewer" "hello" 2>&1); rc=$?
if [ "$rc" = 0 ] && [ "$out" = "opencode run --agent specialist hello" ]; then
    pass "preset agent"
else
    fail "preset agent (rc=$rc, out=$out)"
fi

echo "env override..."
out=$(CCC_REAL_OPENCODE="$MOCK_DIR/opencode" "$CCC" "test prompt" 2>&1); rc=$?
if [ "$rc" = 0 ] && [ "$out" = "opencode run test prompt" ]; then
    pass "env override"
else
    fail "env override (rc=$rc, out=$out)"
fi

echo "unsupported agent warning..."
mkdir -p "$MOCK_DIR/xdg_warn/ccc"
cat > "$MOCK_DIR/xdg_warn/ccc/config.toml" << 'MOCK'
[defaults]
runner = "rc"
MOCK
stdout_file="$MOCK_DIR/stdout"
stderr_file="$MOCK_DIR/stderr"
: > "$stdout_file"
: > "$stderr_file"
PATH="$MOCK_DIR:$PATH" XDG_CONFIG_HOME="$MOCK_DIR/xdg_warn" "$CCC" "@reviewer" "warn me" >"$stdout_file" 2>"$stderr_file"; rc=$?
stdout=$(cat "$stdout_file")
stderr=$(cat "$stderr_file")
if [ "$rc" = 0 ] && [ "$stdout" = "roocode warn me" ] && echo "$stderr" | grep -q 'warning: runner "rc" does not support agents; ignoring @reviewer'; then
    pass "unsupported agent warning"
else
    fail "unsupported agent warning (rc=$rc, stdout=$stdout, stderr=$stderr)"
fi

echo "nonexistent runner..."
out=$(CCC_REAL_OPENCODE=/nonexistent/binary "$CCC" "test" 2>&1); rc=$?
if [ "$rc" = 127 ] && echo "$out" | grep -q "failed to start"; then
    pass "nonexistent runner"
else
    fail "nonexistent runner (rc=$rc, out=$out)"
fi

echo "prompt trimming..."
out=$(CCC_REAL_OPENCODE="$MOCK_DIR/opencode" "$CCC" "  hello  " 2>&1); rc=$?
if [ "$rc" = 0 ] && [ "$out" = "opencode run hello" ]; then
    pass "prompt trimming"
else
    fail "prompt trimming (rc=$rc, out=$out)"
fi

echo "exit code forwarding..."
cat > "$MOCK_DIR/fail_opencode" << 'FAIL_MOCK'
#!/bin/sh
exit 42
FAIL_MOCK
chmod +x "$MOCK_DIR/fail_opencode"
out=$(CCC_REAL_OPENCODE="$MOCK_DIR/fail_opencode" "$CCC" "test" 2>&1); rc=$?
if [ "$rc" = 42 ]; then
    pass "exit code forwarding"
else
    fail "exit code forwarding (rc=$rc, expected 42)"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
