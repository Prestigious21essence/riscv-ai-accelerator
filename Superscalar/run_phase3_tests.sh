#!/bin/bash
# ==============================================================================
# Script: run_phase3_tests.sh
# Description: Automated test runner for Phase 3 of Superscalar Core development.
#              - Builds and executes tb_execution_superscalar (Dual ALUs, Branch
#                Evaluator, Full Crossbar Forwarding, and Pipeline Registers)
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "================================================================================"
echo "          RUNNING PHASE 3 SUPERSCALAR VERIFICATION TEST REGRESSION              "
echo "================================================================================"

mkdir -p build/obj_tb_execution

echo ""
echo "--> Compiling and Running Execution, Branch & Forwarding Regression..."
verilator --binary --timing tb/tb_execution_superscalar.sv \
    rtl/alu_superscalar.sv rtl/branch_evaluator.sv \
    rtl/forwarding_unit_superscalar.sv rtl/pipeline_regs_superscalar.sv \
    --top-module tb_execution_superscalar -Mdir build/obj_tb_execution
./build/obj_tb_execution/Vtb_execution_superscalar

echo ""
echo "================================================================================"
echo "                ALL PHASE 3 SUPERSCALAR TESTS PASSED (0 ERRORS)                 "
echo "================================================================================"

