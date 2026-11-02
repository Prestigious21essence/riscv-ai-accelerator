#!/bin/bash
# ==============================================================================
# Script: run_phase4_tests.sh
# Description: Automated test runner for Phase 4 of Superscalar Core development.
#              - Builds and executes tb_memory_superscalar (Dual-Port Data Memory,
#                Memory Class Arbiter, Store-to-Load Forwarding, MMIO Steering)
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "================================================================================"
echo "          RUNNING PHASE 4 SUPERSCALAR VERIFICATION TEST REGRESSION              "
echo "================================================================================"

mkdir -p build/obj_tb_memory

echo ""
echo "--> Compiling and Running Dual-Port Memory & Arbiter Regression..."
verilator --binary --timing tb/tb_memory_superscalar.sv \
    rtl/data_memory_dualport.sv rtl/mem_class_arbiter.sv \
    --top-module tb_memory_superscalar -Mdir build/obj_tb_memory
./build/obj_tb_memory/Vtb_memory_superscalar

echo ""
echo "================================================================================"
echo "                ALL PHASE 4 SUPERSCALAR TESTS PASSED (0 ERRORS)                 "
echo "================================================================================"

