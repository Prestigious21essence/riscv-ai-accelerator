#!/bin/bash
# ==============================================================================
# Script: run_phase6_tests.sh
# Description: Automated test runner for Phase 6 of Superscalar Core development.
#              - Builds and executes tb_arch_test_superscalar (38/38 RV32I Arch Tests)
#              - Builds and executes tb_superscalar_hazards (Hazard Stress Suite)
#              - Builds and executes tb_superscalar_benchmark32 (32x32 Tiled GEMM Benchmark)
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "================================================================================"
echo "          RUNNING PHASE 6 SUPERSCALAR VERIFICATION TEST REGRESSION              "
echo "================================================================================"

# Common RTL files for the superscalar core and NPU
CORE_RTL="rtl/rv32i_superscalar_npu_core.sv \
    rtl/npu_top_superscalar.sv \
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
    rtl/data_memory_dualport.sv"

# ------------------------------------------------------------------------------
# 1. Architectural Compliance Test Suite (38/38 RV32I Instructions)
# ------------------------------------------------------------------------------
echo ""
echo "--> [1/3] Compiling and Running RV32I Architectural Compliance (38/38)..."
mkdir -p build/obj_tb_arch
verilator --binary --timing -Wno-fatal tb/tb_arch_test_superscalar.sv $CORE_RTL \
    --top-module tb_arch_test_superscalar -Mdir build/obj_tb_arch

cp tb/instr_mem_frontend_test.hex build/obj_tb_arch/instr_mem.hex
(cd build/obj_tb_arch && ./Vtb_arch_test_superscalar +HEX=instr_mem.hex)

# ------------------------------------------------------------------------------
# 2. Superscalar Hazard Stress Suite
# ------------------------------------------------------------------------------
echo ""
echo "--> [2/3] Compiling and Running Superscalar Hazard Stress Suite..."
mkdir -p build/obj_tb_hazards
verilator --binary --timing -Wno-fatal tb/tb_superscalar_hazards.sv $CORE_RTL \
    --top-module tb_superscalar_hazards -Mdir build/obj_tb_hazards

cp tb/instr_mem_frontend_test.hex build/obj_tb_hazards/instr_mem.hex
(cd build/obj_tb_hazards && ./Vtb_superscalar_hazards +HEX=instr_mem.hex)

# ------------------------------------------------------------------------------
# 3. End-to-End 32x32 Tiled GEMM Matrix Multiplication Benchmark
# ------------------------------------------------------------------------------
echo ""
echo "--> [3/3] Compiling and Running End-to-End 32x32 GEMM Benchmark..."
mkdir -p build/obj_tb_benchmark32
verilator --binary --timing -Wno-fatal tb/tb_superscalar_benchmark32.sv $CORE_RTL \
    --top-module tb_superscalar_benchmark32 -Mdir build/obj_tb_benchmark32

cp tb/instr_mem_frontend_test.hex build/obj_tb_benchmark32/instr_mem.hex
(cd .. && ./Superscalar/build/obj_tb_benchmark32/Vtb_superscalar_benchmark32)

echo ""
echo "================================================================================"
echo "                ALL PHASE 6 SUPERSCALAR TESTS PASSED (0 ERRORS)                 "
echo "================================================================================"
