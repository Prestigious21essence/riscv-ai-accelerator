#!/bin/bash
# ==============================================================================
# Script: run_phase2_tests.sh
# Description: Automated test runner for Phase 2 of Superscalar Core development.
#              - Builds and executes tb_decode_superscalar (Dual decoders & imm_gen)
#              - Builds and executes tb_hazard_unit_superscalar (Dynamic issue & hazards)
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "================================================================================"
echo "          RUNNING PHASE 2 SUPERSCALAR VERIFICATION TEST REGRESSION              "
echo "================================================================================"

mkdir -p build/obj_tb_decode build/obj_tb_hazard

echo ""
echo "--> [1/2] Compiling and Running Dual Decode & ImmGen Regression..."
verilator --binary --timing tb/tb_decode_superscalar.sv rtl/control_superscalar.sv rtl/imm_gen_superscalar.sv \
    --top-module tb_decode_superscalar -Mdir build/obj_tb_decode
./build/obj_tb_decode/Vtb_decode_superscalar

echo ""
echo "--> [2/2] Compiling and Running Dynamic Hazard & Issue Unit Regression..."
verilator --binary --timing tb/tb_hazard_unit_superscalar.sv rtl/hazard_unit_superscalar.sv \
    --top-module tb_hazard_unit_superscalar -Mdir build/obj_tb_hazard
./build/obj_tb_hazard/Vtb_hazard_unit_superscalar

echo ""
echo "================================================================================"
echo "                ALL PHASE 2 SUPERSCALAR TESTS PASSED (0 ERRORS)                 "
echo "================================================================================"

