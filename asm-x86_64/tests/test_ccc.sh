#!/bin/sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CCC="$SCRIPT_DIR/../ccc"

MOCK_DIR=$(mktemp -d)
trap 'rm -rf "$MOCK_DIR"' EXIT

cat > "$MOCK_DIR/opencode" << 'MOCK'
#!/bin/sh
if [ "$1" != "run" ]; then
  exit 9
fi
shift
printf "opencode run %s\n" "$1"
MOCK
chmod +x "$MOCK_DIR/opencode"

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

echo "happy path..."
out=$(CCC_REAL_OPENCODE="$MOCK_DIR/opencode" "$CCC" "hello world" 2>&1); rc=$?
if [ "$rc" = 0 ] && [ "$out" = "opencode run hello world" ]; then
    pass "happy path"
else
    fail "happy path (rc=$rc, out=$out)"
fi

echo "env override..."
out=$(CCC_REAL_OPENCODE="$MOCK_DIR/opencode" "$CCC" "test prompt" 2>&1); rc=$?
if [ "$rc" = 0 ] && [ "$out" = "opencode run test prompt" ]; then
    pass "env override"
else
    fail "env override (rc=$rc, out=$out)"
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
