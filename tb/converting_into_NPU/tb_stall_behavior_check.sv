`timescale 1ns/1ps

module tb_stall_behavior_check;
    logic clk = 0;
    logic rst = 1;
    int errors = 0;

    rv32i_pipeline_stallbranch_core core_dut (.clk(clk), .rst(rst));
    always #5 clk = ~clk;

    task check(string name, logic condition);
        if (!condition) begin
            $display("FAIL: %s", name);
            errors++;
        end else begin
            $display("PASS: %s", name);
        end
    endtask

    initial begin
        $readmemh("tb/rv32i_pipelined_stallbranch/instr_mem_stallbranch_demo.hex", core_dut.imem.mem);
        @(negedge clk);
        rst = 0;

        // In instr_mem_stallbranch_demo.hex:
        // PC 0x00: addi x1, x0, 10
        // PC 0x04: addi x2, x1, 20
        // PC 0x08: add  x3, x1, x2
        // PC 0x0c: addi x4, x0, 100
        // PC 0x10: nop
        // PC 0x14: add  x5, x4, x1
        // PC 0x18: sw   x1, 0(x0)
        // PC 0x1c: lw   x6, 0(x0)
        // PC 0x20: addi x7, x6, 5
        // PC 0x24: beq  x1, x6, 8 (Branch to 0x2c)
        // PC 0x28: addi x8, x0, 99 (Skipped)
        // PC 0x2c: addi x9, x0, 77 (Target)

        for (int cyc = 1; cyc <= 25; cyc++) begin
            @(negedge clk);
            
            // Monitor any cycle where branch/jump is in EX
            if (core_dut.ex_branch_or_jump) begin
                $display("[Cycle %0d] Branch in EX: pc=%h | ex_branch_or_jump=%b, pc_write=%b, if_id_write=%b, flush_if_id=%b, flush_id_ex=%b, ex_resolved_pc=%h",
                    cyc, core_dut.ex_pc,
                    core_dut.ex_branch_or_jump, core_dut.pc_write, core_dut.if_id_write,
                    core_dut.flush_if_id, core_dut.flush_id_ex, core_dut.ex_resolved_pc);

                // CRITICAL CHECKS when branch is in EX:
                // 1. Fetch to IF/ID MUST BE STALLED (if_id_write == 0)
                check("When branch is in EX: if_id_write MUST be 0 (fetching to IF/ID stalled)", core_dut.if_id_write == 1'b0);

                // 2. IF/ID MUST NOT be flushed (flush_if_id == 0)
                check("When branch is in EX: flush_if_id MUST be 0 (no speculative fetch/flush)", core_dut.flush_if_id == 1'b0);

                // 3. ID/EX MUST NOT be flushed (flush_id_ex == 0)
                check("When branch is in EX: flush_id_ex MUST be 0", core_dut.flush_id_ex == 1'b0);

                // 4. PC write MUST be enabled to latch resolved target on clock edge
                check("When branch is in EX: pc_write MUST be 1 (updates to resolved target on edge)", core_dut.pc_write == 1'b1);
            end

            // Monitor cycle where branch/jump arrives in ID
            if (core_dut.id_branch_or_jump && !core_dut.hazard_ctrl.load_use_hazard) begin
                $display("[Cycle %0d] Branch in ID: pc=%h instr=%h | pc_write=%b, if_id_write=%b, flush_if_id=%b",
                    cyc, core_dut.id_pc, core_dut.id_instr,
                    core_dut.pc_write, core_dut.if_id_write, core_dut.flush_if_id);
                check("When branch in ID: pc_write is 0 (freeze PC)", core_dut.pc_write == 1'b0);
            end
        end

        // Check final register state to confirm 0x28 (addi x8, x0, 99) was skipped
        check("x8 remained 0 (addi x8, x0, 99 was skipped)", core_dut.regfile.regs[8] == 32'd0);
        check("x9 was written to 77 (branch target executed)", core_dut.regfile.regs[9] == 32'd77);

        if (errors == 0) begin
            $display("\n=======================================================");
            $display("ALL STALL BEHAVIOR CHECKS PASSED PERFECTLY (0 ERRORS)");
            $display("=======================================================\n");
        end else begin
            $display("\nFAILED WITH %0d ERRORS\n", errors);
        end
        $finish;
    end
endmodule
