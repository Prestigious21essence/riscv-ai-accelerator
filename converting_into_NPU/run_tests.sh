#!/usr/bin/env bash
# ==============================================================================
# converting_into_NPU/run_tests.sh
#
# Complete verification runner for the RV32I Always-Stall Pipeline & NPU Coprocessor
# ==============================================================================

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RTL_DIR="$DIR/rtl"
TB_DIR="$DIR/tb"
BUILD_DIR="$DIR/build"

mkdir -p "$BUILD_DIR"

echo "================================================================================"
echo "          VERIFYING BASE STALL PIPELINE & NPU IN converting_into_NPU            "
echo "================================================================================"

# 1. Core basic functional regression
echo "[1/7] Running Core Basic Regression..."
cp "$DIR/../instr_mem.hex" "$BUILD_DIR/instr_mem.hex"
verilator --binary --timing "$TB_DIR/tb_pipeline_stallbranch_core.sv" \
  "$RTL_DIR"/*.sv \
  --top-module tb_pipeline_stallbranch_core -Mdir "$BUILD_DIR/obj_core" > /dev/null
(cd "$BUILD_DIR" && ./obj_core/Vtb_pipeline_stallbranch_core)

# 2. Hazard stress test
echo ""
echo "[2/7] Running Hazard Stress Regression..."
cp "$DIR/../tb/rv32i_pipelined/instr_mem_hazards.hex" "$BUILD_DIR/instr_mem.hex"
verilator --binary --timing "$TB_DIR/tb_pipeline_stallbranch_hazards.sv" \
  "$RTL_DIR"/*.sv \
  --top-module tb_pipeline_stallbranch_hazards -Mdir "$BUILD_DIR/obj_hazards" > /dev/null
(cd "$BUILD_DIR" && ./obj_hazards/Vtb_pipeline_stallbranch_hazards)

# 3. Branch & JALR stress test
echo ""
echo "[3/7] Running Branch & JALR Regression..."
cp "$DIR/../tb/rv32i/instr_mem_branch_jalr.hex" "$BUILD_DIR/instr_mem.hex"
verilator --binary --timing "$TB_DIR/tb_pipeline_stallbranch_branch_jalr.sv" \
  "$RTL_DIR"/*.sv \
  --top-module tb_pipeline_stallbranch_branch_jalr -Mdir "$BUILD_DIR/obj_branch" > /dev/null
(cd "$BUILD_DIR" && ./obj_branch/Vtb_pipeline_stallbranch_branch_jalr)

# 4. Stall behavior check
echo ""
echo "[4/7] Running Stall Behavior Check..."
cp "$DIR/../tb/rv32i_pipelined_stallbranch/instr_mem_stallbranch_demo.hex" "$BUILD_DIR/instr_mem.hex"
verilator --binary --timing "$TB_DIR/tb_stall_behavior_check.sv" \
  "$RTL_DIR"/*.sv \
  --top-module tb_stall_behavior_check -Mdir "$BUILD_DIR/obj_stall_check" > /dev/null
(cd "$BUILD_DIR" && ./obj_stall_check/Vtb_stall_behavior_check)

# 5. Standalone NPU accelerator test (Dimensions, 4x4 Identity, 16x16 4096-MAC Stress Test)
echo ""
echo "[5/7] Running Standalone NPU Accelerator Verification..."
verilator --binary --timing "$TB_DIR/tb_npu_top.sv" "$RTL_DIR/npu_top.sv" \
  --top-module tb_npu_top -Mdir "$BUILD_DIR/obj_npu" > /dev/null
"$BUILD_DIR/obj_npu/Vtb_npu_top"

# 6. Full-system CPU + NPU co-simulation test
echo ""
echo "[6/7] Running Full-System CPU + NPU Co-Simulation Regression..."
python3 "$DIR/tests/gen_npu_test_hex.py" > /dev/null
mkdir -p "$BUILD_DIR/obj_system"
cp "$TB_DIR/instr_mem_npu.hex" "$BUILD_DIR/obj_system/instr_mem.hex"
verilator --binary --timing "$TB_DIR/tb_pipeline_npu_core.sv" "$RTL_DIR"/*.sv \
  --top-module tb_pipeline_npu_core -Mdir "$BUILD_DIR/obj_system" > /dev/null
(cd "$BUILD_DIR/obj_system" && ./Vtb_pipeline_npu_core)

# 7. Level 3 Full 32x32 End-to-End Benchmark Test (Real data from matmul_32_t2_s32_O2.c)
echo ""
echo "[7/7] Running Level 3: 32x32 Tiled GEMM Benchmark Regression..."
python3 "$DIR/tests/gen_npu_benchmark32.py" > /dev/null
mkdir -p "$BUILD_DIR/obj_benchmark32"
cp "$TB_DIR/instr_mem_benchmark32.hex" "$BUILD_DIR/obj_benchmark32/instr_mem.hex"
cp "$TB_DIR/data_a.hex" "$BUILD_DIR/obj_benchmark32/data_a.hex"
cp "$TB_DIR/data_b.hex" "$BUILD_DIR/obj_benchmark32/data_b.hex"
cp "$TB_DIR/golden_c.hex" "$BUILD_DIR/obj_benchmark32/golden_c.hex"
verilator --binary --timing "$TB_DIR/tb_pipeline_npu_benchmark32.sv" "$RTL_DIR"/*.sv \
  --top-module tb_pipeline_npu_benchmark32 -Mdir "$BUILD_DIR/obj_benchmark32" > /dev/null
(cd "$BUILD_DIR/obj_benchmark32" && ./Vtb_pipeline_npu_benchmark32)

echo ""
echo "================================================================================"
echo "          ALL 7/7 CORE & NPU TESTS PASSED FOR converting_into_NPU               "
echo "================================================================================"
