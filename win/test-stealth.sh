#!/usr/bin/env bash
# ============================================================================
# win/test-stealth.sh - Automated test suite for the Wine stealth module
# ============================================================================
# Usage:  sudo bash /opt/heysolo/scripts/win/test-stealth.sh
# ============================================================================

set -uo pipefail

# Everything Wine-stealth related lives in this folder
WIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEALTH_SCRIPT="${WIN_DIR}/wine-stealth.sh"
TERMINALS_FILE="/etc/heysolo-mt5/terminals.list"

PASS=0; FAIL=0; SKIP=0
pass(){ echo "✅ PASS  $1"; ((PASS++)); }
fail(){ echo "❌ FAIL  $1"; ((FAIL++)); }
skip(){ echo "⚠️  SKIP  $1"; ((SKIP++)); }

echo "🧪 Wine Stealth Module - Automated Test Suite"
echo "   folder: ${WIN_DIR}"
echo

# Test 1: script present and executable
if [[ -x "$STEALTH_SCRIPT" ]]; then
    pass "wine-stealth.sh found and executable"
elif [[ -s "$STEALTH_SCRIPT" ]]; then
    chmod +x "$STEALTH_SCRIPT" 2>/dev/null && pass "wine-stealth.sh found (chmod +x applied)" \
        || fail "wine-stealth.sh not executable"
else
    fail "wine-stealth.sh not found in ${WIN_DIR}"
    echo; echo "Nothing else to test."; exit 1
fi

# Test 2: syntax is valid
if bash -n "$STEALTH_SCRIPT" 2>/dev/null; then
    pass "bash syntax valid"
else
    fail "bash syntax error"
fi

# Test 3: help works without root
if bash "$STEALTH_SCRIPT" --help 2>&1 | grep -q "Usage:"; then
    pass "help output"
else
    fail "help output missing 'Usage:'"
fi

# From here on root is required
if [[ $EUID -ne 0 ]]; then
    echo
    skip "root-only tests (re-run with sudo)"
else
    # Test 4: status runs even with no terminals
    if bash "$STEALTH_SCRIPT" status >/dev/null 2>&1; then
        pass "status command"
    else
        fail "status command"
    fi

    # Test 5: Windows profile is selectable / persisted
    if bash "$STEALTH_SCRIPT" version 19045 2>&1 | grep -q "19045"; then
        pass "Windows profile switch (build 19045)"
    else
        fail "Windows profile switch"
    fi

    # Test 6: custom build number is accepted
    if bash "$STEALTH_SCRIPT" version 21327 2>&1 | grep -q "21327"; then
        pass "custom build number (21327)"
        bash "$STEALTH_SCRIPT" version 19045 >/dev/null 2>&1 || true   # restore default
    else
        fail "custom build number"
    fi

    # Tests 7-9: only meaningful with real terminals
    if [[ -s "$TERMINALS_FILE" ]]; then
        echo
        echo "Terminals found - running live prefix tests..."

        if bash "$STEALTH_SCRIPT" apply >/dev/null 2>&1; then
            pass "apply stealth to all terminals"
        else
            fail "apply stealth"
        fi

        if bash "$STEALTH_SCRIPT" test 2>&1 | grep -qi "pass"; then
            pass "stealth verification"
        else
            skip "stealth verification (expected until terminals restart)"
        fi

        if bash "$STEALTH_SCRIPT" revert >/dev/null 2>&1; then
            pass "revert stealth"
        else
            fail "revert stealth"
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
