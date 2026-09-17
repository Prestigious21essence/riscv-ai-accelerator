# Branch Handling: Speculative (Predict Not-Taken) vs. Always-Stall

This document explains the architecture, timing, hardware trade-offs, and verification results of the **Always-Stall on Branch** pipelined core located in [`rtl/rv32i_pipelined_stallbranch/`](file:///home/enovo/riscv-ai-accelerator/rtl/rv32i_pipelined_stallbranch/).

Both pipelined designs pass **100% of the official RISC-V architectural compliance tests (38/38 PASS, 0 differences vs Spike)**:
- **Design A (`rtl/rv32i_pipelined/`)**: Speculative execution with Predict-Not-Taken (2-cycle penalty on taken branches, 0-cycle penalty on not-taken branches).
- **Design B (`rtl/rv32i_pipelined_stallbranch/`)**: Non-speculative execution with Always-Stall (2-cycle fixed stall on all branches and jumps, 0 wrong-path instructions fetched).

---

## 1. Architectural Comparison

```
+-----------------------------------+-----------------------------------+
|   Predict-Not-Taken (Speculative) |    Always-Stall (Non-Speculative) |
|      [rtl/rv32i_pipelined/]       | [rtl/rv32i_pipelined_stallbranch/]|
+-----------------------------------+-----------------------------------+
| - Fetches PC+4 speculatively      | - Freezes PC fetch when branch    |
|   behind every branch.            |   arrives in ID stage.            |
| - Resolves condition in EX stage. | - Resolves condition in EX stage. |
| - If Taken:                       | - In EX, updates PC to target or  |
|   Flushes IF/ID & ID/EX (2 bubbles|   fallthrough address.            |
| - If Not-Taken:                   | - Both Taken & Not-Taken incur    |
|   0 penalty (speculation correct).|   2 stall cycles.                 |
| - Requires pipeline flush logic.  | - Zero speculative instructions   |
|                                   |   ever enter the datapath.        |
+-----------------------------------+-----------------------------------+
```

---

## 2. Cycle-by-Cycle Timing Breakdown

### Scenario: Branch Instruction at Address `0x100`

#### A. When Branch is TAKEN (Target = `0x200`)

##### 1. Always-Stall Core (`rtl/rv32i_pipelined_stallbranch/`):
```
Cycle 1: IF: Fetch BEQ at 0x100. Next sequential PC becomes 0x104.
Cycle 2: ID: BEQ decoded in ID (id_branch_or_jump = 1).
         Fetch Stalls:
         - pc_write = 0 (PC held at 0x104)
         - flush_if_id = 1 (discards 0x104, inserts NOP bubble into IF/ID)
         - BEQ advances to EX stage.
Cycle 3: EX: BEQ in EX stage.
         Condition evaluates to TAKEN!
         - ex_resolved_pc = 0x200 (target address)
         - pc_write = 1 (PC updates to 0x200 on next clock edge)
         - flush_if_id = 1 (inserts NOP bubble into IF/ID)
         - ID has NOP bubble from Cycle 2.
Cycle 4: IF: Fetches target instruction at 0x200.
         ID: NOP bubble.
         EX: NOP bubble.
         MEM: BEQ in MEM.
Cycle 5: ID: Decodes target instruction at 0x200.
         EX: NOP bubble.
         MEM: NOP bubble.
         WB: BEQ in WB.
```
**Outcome**: Exactly 2 bubble cycles. Zero instructions on the wrong path are executed.

---

#### B. When Branch is NOT TAKEN (Fallthrough = `0x104`)

##### 1. Always-Stall Core (`rtl/rv32i_pipelined_stallbranch/`):
```
Cycle 1: IF: Fetch BEQ at 0x100.
Cycle 2: ID: BEQ decoded in ID.
         Fetch Stalls:
         - pc_write = 0 (PC held at 0x104)
         - flush_if_id = 1 (NOP inserted into IF/ID)
         - BEQ advances to EX stage.
Cycle 3: EX: BEQ in EX stage.
         Condition evaluates to NOT TAKEN!
         - ex_resolved_pc = 0x104 (fallthrough address: ex_pc + 4)
         - pc_write = 1 (PC updates to 0x104 on next clock edge)
         - flush_if_id = 1 (NOP inserted into IF/ID)
Cycle 4: IF: Fetches fallthrough instruction at 0x104.
Cycle 5: ID: Decodes fallthrough instruction at 0x104.
```
**Outcome**: 2 bubble cycles. Simple, non-speculative, deterministic behavior.

##### 2. Predict-Not-Taken Core (`rtl/rv32i_pipelined/`):
```
Cycle 1: IF: Fetch BEQ at 0x100.
Cycle 2: ID: BEQ in ID. IF fetches 0x104 speculatively.
Cycle 3: EX: BEQ in EX. Condition = NOT TAKEN. No flush!
         IF fetches 0x108. ID decodes 0x104.
```
**Outcome**: 0 bubble cycles (1 cycle per instruction maintained).

---

## 3. Hazard Unit Control Logic (`hazard_unit_stallbranch.sv`)

The control logic manages priority between load-use data hazards and branch stalls:

```systemverilog
always_comb begin
    if (load_use_hazard) begin
        // Priority 1: Load-use stall takes precedence.
        // If a branch in ID depends on a load currently in EX,
        // freeze PC and IF/ID, and insert bubble into ID/EX.
        pc_write    = 1'b0;
        if_id_write = 1'b0;
        flush_if_id = 1'b0;
        flush_id_ex = 1'b1;
    end else if (ex_branch_or_jump) begin
        // Priority 2: Branch/jump resolves in EX.
        // PC is updated to the resolved target or fallthrough address.
        // Insert bubble into IF/ID for this transition cycle.
        pc_write    = 1'b1;
        if_id_write = 1'b1;
        flush_if_id = 1'b1;
        flush_id_ex = 1'b0;
    end else if (id_branch_or_jump) begin
        // Priority 3: Branch/jump arrives in ID.
        // Freeze instruction fetch until branch reaches EX and resolves.
        // Discard IF, allow branch in ID to advance to EX.
        pc_write    = 1'b0;
        if_id_write = 1'b1;
        flush_if_id = 1'b1;
        flush_id_ex = 1'b0;
    end else begin
        // Normal sequential pipelined execution
        pc_write    = 1'b1;
        if_id_write = 1'b1;
        flush_if_id = 1'b0;
        flush_id_ex = 1'b0;
    end
end
```

---

## 4. Verification Results

### Unit Tests
1. **Core Basic Tests (`tb_pipeline_stallbranch_core.sv`)**: **7/7 PASS**
2. **Branch & JALR Stress Tests (`tb_pipeline_stallbranch_branch_jalr.sv`)**: **19/19 PASS**
   - Verified across BEQ, BNE, BLT, BGE, BLTU, BGEU (both taken and not-taken cases) + JAL + JALR.
   - 0 skipped instructions leaked into registers.
3. **Hazard Tests (`tb_pipeline_stallbranch_hazards.sv`)**: **11/11 PASS**
   - Verified EX-to-EX forwarding, MEM-to-EX forwarding, load-use stalls, store forwarding, and write-first regfile bypass.

### Full RISC-V Architectural Compliance (`riscv-arch-test`)
Verified bit-for-bit against the Spike golden reference simulator via [`verification/arch-test/run_stallbranch_suite.sh`](file:///home/enovo/riscv-ai-accelerator/verification/arch-test/run_stallbranch_suite.sh):
```text
=== 38 passed, 0 failed (of 38 total) ===
```
Both the speculative core (`run_pipeline_suite.sh`) and the stall-on-branch core (`run_stallbranch_suite.sh`) achieve 100% architectural compliance.

