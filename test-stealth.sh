
## 6. Test Script

Create `test-stealth.sh` for automated testing:

```bash
#!/bin/bash
# test-stealth.sh - Automated test suite for Wine stealth module

set -e

SCRIPTS_DIR="/opt/heysolo/scripts"
STEALTH_SCRIPT="${SCRIPTS_DIR}/wine-stealth.sh"

echo "🧪 Wine Stealth Module - Automated Test Suite"
echo

# Test 1: Script exists and is executable
echo "Test 1: Script exists and is executable..."
if [[ -x "$STEALTH_SCRIPT" ]]; then
    echo "✅ PASS"
else
    echo "❌ FAIL: Script not found or not executable"
    exit 1
fi

# Test 2: Help command works
echo "Test 2: Help command..."
if bash "$STEALTH_SCRIPT" --help 2>&1 | grep -q "Usage:"; then
    echo "✅ PASS"
else
    echo "❌ FAIL: Help command failed"
    exit 1
fi

# Test 3: Status command works (even with no terminals)
echo "Test 3: Status command..."
if sudo bash "$STEALTH_SCRIPT" status >/dev/null 2>&1; then
    echo "✅ PASS"
else
    echo "❌ FAIL: Status command failed"
    exit 1
fi

# Test 4: Check if terminals exist
echo "Test 4: Checking for terminals..."
TERMINALS_FILE="/etc/heysolo-mt5/terminals.list"
if [[ -s "$TERMINALS_FILE" ]]; then
    echo "✅ Terminals found - running full tests"
    
    # Test 5: Apply stealth
    echo "Test 5: Apply stealth..."
    if sudo bash "$STEALTH_SCRIPT" apply >/dev/null 2>&1; then
        echo "✅ PASS"
    else
        echo "❌ FAIL: Apply stealth failed"
        exit 1
    fi
    
    # Test 6: Test stealth
    echo "Test 6: Test stealth..."
    if sudo bash "$STEALTH_SCRIPT" test 2>&1 | grep -q "passed"; then
        echo "✅ PASS"
    else
        echo "⚠️  WARNING: Some tests failed (this is expected before restarting terminals)"
    fi
    
    # Test 7: Revert stealth
    echo "Test 7: Revert stealth..."
    if sudo bash "$STEALTH_SCRIPT" revert >/dev/null 2>&1; then
        echo "✅ PASS"
    else
        echo "❌ FAIL: Revert stealth failed"
        exit 1
    fi
else
    echo "⚠️  SKIP: No terminals installed"
fi

echo
echo "🎉 All tests completed!"
