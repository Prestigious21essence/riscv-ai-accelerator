#!/bin/bash
# ==============================================================================
# Script: run_all_tests.sh
# Description: Master regression runner for Superscalar Core development.
#              Executes all completed phase regressions (Phases 1 - 4).
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "================================================================================"
echo "          RUNNING MASTER SUPERSCALAR VERIFICATION TEST REGRESSION               "
echo "================================================================================"

echo ""
echo "===>>> EXECUTING PHASE 1 TESTS <<<==="
./run_phase1_tests.sh

echo ""
echo "===>>> EXECUTING PHASE 2 TESTS <<<==="
./run_phase2_tests.sh

echo ""
echo "===>>> EXECUTING PHASE 3 TESTS <<<==="
./run_phase3_tests.sh

echo ""
echo "===>>> EXECUTING PHASE 4 TESTS <<<==="
./run_phase4_tests.sh

echo ""
echo "===>>> EXECUTING PHASE 5 TESTS <<<==="
./run_phase5_tests.sh

echo ""
echo "===>>> EXECUTING PHASE 6 TESTS <<<==="
./run_phase6_tests.sh

echo ""
echo "================================================================================"
echo "          ALL COMPLETED SUPERSCALAR PHASES PASSED WITH ZERO ERRORS!             "
echo "================================================================================"
