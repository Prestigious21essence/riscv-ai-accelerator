#!/bin/bash
# ==============================================================================
# Script: run_phase5_tests.sh
# Description: Automated test runner for Phase 5 of Superscalar Core development.
#              - Builds and executes tb_superscalar_npu (Concurrent Double-Buffered
#                NPU Accelerator, Command FIFO, Dual-Channel Streaming & Top Core)
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "================================================================================"
echo "          RUNNING PHASE 5 SUPERSCALAR VERIFICATION TEST REGRESSION              "
echo "================================================================================"

mkdir -p build/obj_tb_npu

echo ""
echo "--> Compiling and Running Concurrent NPU & Core Integration Regression..."
verilator --binary --timing tb/tb_superscalar_npu.sv \
    rtl/npu_top_superscalar.sv \
    rtl/rv32i_superscalar_npu_core.sv \
    rtl/fetch_unit_superscalar.sv \
    rtl/pc_superscalar.sv \
    rtl/instruction_memory_64.sv \
    rtl/btb_128.sv \
    rtl/control_superscalar.sv \
    rtl/imm_gen_superscalar.sv \
    rtl/register_file_4r2w.sv \
    rtl/hazard_unit_superscalar.sv \
    rtl/pipeline_regs_superscalar.sv \
    rtl/forwarding_unit_superscalar.sv \
    rtl/alu_superscalar.sv \
    rtl/branch_evaluator.sv \
    rtl/mem_class_arbiter.sv \
    rtl/data_memory_dualport.sv \
    --top-module tb_superscalar_npu -Mdir build/obj_tb_npu

cp tb/instr_mem_frontend_test.hex build/obj_tb_npu/instr_mem.hex
(cd build/obj_tb_npu && ./Vtb_superscalar_npu +HEX=instr_mem.hex)

echo ""
echo "================================================================================"
echo "                ALL PHASE 5 SUPERSCALAR TESTS PASSED (0 ERRORS)                 "
echo "================================================================================"

