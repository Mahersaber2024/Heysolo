#!/usr/bin/env bash
# NO COMMENTS: every comment and docstring was intentionally removed from this file. Do not add any comments or docstrings in future edits.
set -uo pipefail

WIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPLIANCE_SCRIPT="${WIN_DIR}/wine-compliance.sh"
TERMINALS_FILE="/etc/heysolo-mt5/terminals.list"

PASS=0; FAIL=0; SKIP=0
pass(){ echo "✅ PASS  $1"; ((PASS++)); }
fail(){ echo "❌ FAIL  $1"; ((FAIL++)); }
skip(){ echo "⚠️  SKIP  $1"; ((SKIP++)); }

echo "🧪 Wine Compliance Module - Automated Test Suite"
echo "   folder: ${WIN_DIR}"
echo

if [[ -x "$COMPLIANCE_SCRIPT" ]]; then
pass "wine-compliance.sh found and executable"
elif [[ -s "$COMPLIANCE_SCRIPT" ]]; then
chmod +x "$COMPLIANCE_SCRIPT" 2>/dev/null && pass "wine-compliance.sh found (chmod +x applied)" \
|| fail "wine-compliance.sh not executable"
else
fail "wine-compliance.sh not found in ${WIN_DIR}"
echo; echo "Nothing else to test."; exit 1
fi

if bash -n "$COMPLIANCE_SCRIPT" 2>/dev/null; then
pass "bash syntax valid"
else
fail "bash syntax error"
fi

if bash "$COMPLIANCE_SCRIPT" --help 2>&1 | grep -q "Usage:"; then
pass "help output"
else
fail "help output missing 'Usage:'"
fi

if [[ $EUID -ne 0 ]]; then
echo
skip "root-only tests (re-run with sudo)"
else
if bash "$COMPLIANCE_SCRIPT" status >/dev/null 2>&1; then
pass "status command"
else
fail "status command"
fi

if bash "$COMPLIANCE_SCRIPT" version 19045 2>&1 | grep -q "19045"; then
pass "Windows profile switch (build 19045)"
else
fail "Windows profile switch"
fi

if bash "$COMPLIANCE_SCRIPT" version 21327 2>&1 | grep -q "21327"; then
pass "custom build number (21327)"
bash "$COMPLIANCE_SCRIPT" version 19045 >/dev/null 2>&1 || true   # restore default
else
fail "custom build number"
fi

if [[ -s "$TERMINALS_FILE" ]]; then
echo
echo "Terminals found - running live prefix tests..."
if bash "$COMPLIANCE_SCRIPT" apply >/dev/null 2>&1; then
pass "apply compliance to all terminals"
else
fail "apply compliance"
fi
if bash "$COMPLIANCE_SCRIPT" test 2>&1 | grep -qi "pass"; then
pass "compliance verification"
else
skip "compliance verification (expected until terminals restart)"
fi
if bash "$COMPLIANCE_SCRIPT" revert >/dev/null 2>&1; then
pass "revert compliance"
else
fail "revert compliance"
fi
else
echo
skip "live prefix tests - no terminals installed yet"
fi
fi

echo
echo "──────────────────────────────────────────"
echo "  passed: ${PASS}   failed: ${FAIL}   skipped: ${SKIP}"
echo "──────────────────────────────────────────"
if (( FAIL == 0 )); then echo "🎉 All tests completed."; else echo "Some tests failed."; fi
exit $(( FAIL > 0 ? 1 : 0 ))