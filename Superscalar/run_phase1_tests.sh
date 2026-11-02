#!/bin/bash
# ==============================================================================
# Script: run_phase1_tests.sh
# Description: Automated test runner for Phase 1 of Superscalar Core development.
#              - Builds and executes tb_regfile_4r2w (4R/2W register file)
#              - Builds and executes tb_frontend_superscalar (64-bit fetch, PC, BTB)
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "================================================================================"
echo "          RUNNING PHASE 1 SUPERSCALAR VERIFICATION TEST REGRESSION              "
echo "================================================================================"

mkdir -p build/obj_tb_rf build/obj_tb_frontend

echo ""
echo "--> [1/2] Compiling and Running 4R/2W Register File Regression..."
verilator --binary --timing tb/tb_regfile_4r2w.sv rtl/register_file_4r2w.sv \
    --top-module tb_regfile_4r2w -Mdir build/obj_tb_rf
./build/obj_tb_rf/Vtb_regfile_4r2w

echo ""
echo "--> [2/2] Compiling and Running 64-bit Superscalar Frontend Regression..."
verilator --binary --timing tb/tb_frontend_superscalar.sv rtl/fetch_unit_superscalar.sv \
    rtl/pc_superscalar.sv rtl/instruction_memory_64.sv rtl/btb_128.sv \
    --top-module tb_frontend_superscalar -Mdir build/obj_tb_frontend

cp tb/instr_mem_frontend_test.hex build/obj_tb_frontend/instr_mem.hex
(cd build/obj_tb_frontend && ./Vtb_frontend_superscalar +HEX=instr_mem.hex)

echo ""
echo "================================================================================"
echo "                ALL PHASE 1 SUPERSCALAR TESTS PASSED (0 ERRORS)                 "
echo "================================================================================"

