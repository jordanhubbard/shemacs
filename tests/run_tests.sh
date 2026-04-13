#!/bin/bash
# Run all expect-based integration tests for em
# Usage: ./tests/run_tests.sh
# Requires: expect, bash 4+, zsh 5+, sheme (bs.sh)

set -euo pipefail

cd "$(dirname "$0")/.."

PASS=0
FAIL=0
ERRORS=()

run_test() {
    local name="$1" script="$2"
    printf "  %-40s " "$name"
    if output=$(expect "$script" 2>&1); then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        echo "FAIL"
        ERRORS+=("$name: $output")
        FAIL=$((FAIL + 1))
    fi
}

echo "=== em integration tests ==="
echo ""

# Syntax checks
echo "Syntax checks:"
printf "  %-40s " "bash syntax (bash -n em.sh)"
if bash -n em.sh 2>&1; then
    echo "PASS"
    PASS=$((PASS + 1))
else
    echo "FAIL"
    FAIL=$((FAIL + 1))
fi

if command -v zsh >/dev/null 2>&1; then
    printf "  %-40s " "zsh syntax (zsh -n em.zsh)"
    if zsh -n em.zsh 2>&1; then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        echo "FAIL"
        FAIL=$((FAIL + 1))
    fi
fi
echo ""

# Check sheme is available
if ! bash -c 'source ~/.bs.sh 2>/dev/null && type bs &>/dev/null' 2>/dev/null; then
    echo "ERROR: sheme (bs.sh) not found — install from https://github.com/jordanhubbard/sheme"
    echo ""
    echo "=== Results: $PASS passed, $FAIL failed ==="
    exit 1
fi

# Check if expect is available for interactive tests
if ! command -v expect >/dev/null 2>&1; then
    echo "Interactive tests: SKIPPED (expect not installed)"
    echo ""
    echo "=== Results: $PASS passed, $FAIL failed ==="
    exit $((FAIL > 0 ? 1 : 0))
fi

# Editor tests
echo "Editor tests:"
run_test "start and quit" tests/test_scm_start_quit.exp
run_test "open file" tests/test_scm_open_file.exp
run_test "save file" tests/test_scm_save_file.exp
run_test "upcase word (M-u)" tests/test_scm_upcase.exp
run_test "isearch highlight" tests/test_scm_isearch.exp
run_test "cache round-trip" tests/test_scm_cache.exp
echo ""

# Summary
echo "=== Results: $PASS passed, $FAIL failed ==="

if ((FAIL > 0)); then
    echo ""
    echo "Failures:"
    for err in "${ERRORS[@]}"; do
        echo "  - $err" | head -3
    done
    exit 1
fi
