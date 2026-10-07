// =============================================================================
// Trace Testbench for RV32I Pipeline + NPU Accelerator
// File: tb_pipeline_npu_trace.sv
//
// Description:
//   Simulates the combined CPU + NPU system, capturing cycle-by-cycle
//   telemetry from both the 5-stage CPU pipeline and the NPU coprocessor,
//   serializing it to cycle_dump_npu.json for the interactive visualizer.
// =============================================================================

`timescale 1ns / 1ps

module tb_pipeline_npu_trace #(
    parameter MEM_WORDS = 1024
);

    logic clk = 0;
    logic rst = 1;

    rv32i_pipeline_stallbranch_core #(.MEM_WORDS(MEM_WORDS)) core_dut (
        .clk(clk),
        .rst(rst)
    );

    always #5 clk = ~clk;

    // Shadow pipeline registers
    logic [31:0] tb_ex_instr,  tb_ex_pc;
    logic [31:0] tb_mem_instr, tb_mem_pc;
    logic [31:0] tb_wb_instr,  tb_wb_pc;

    int cycle_cnt = 0;
    int max_cycles = 70;
    string dump_file = "cycle_dump_npu.json";
    int fd;
    bit first_entry = 1;

    always_ff @(posedge clk) begin
        if (rst) begin
            tb_ex_instr  <= 32'h00000013;
            tb_ex_pc     <= 32'b0;
            tb_mem_instr <= 32'h00000013;
            tb_mem_pc    <= 32'b0;
            tb_wb_instr  <= 32'h00000013;
            tb_wb_pc     <= 32'b0;
        end else begin
            if (core_dut.flush_id_ex) begin
                tb_ex_instr <= 32'h00000013;
                tb_ex_pc    <= 32'b0;
            end else begin
                tb_ex_instr <= core_dut.id_instr;
                tb_ex_pc    <= core_dut.id_pc;
            end

            tb_mem_instr <= tb_ex_instr;
            tb_mem_pc    <= tb_ex_pc;

            tb_wb_instr  <= tb_mem_instr;
            tb_wb_pc     <= tb_mem_pc;
        end
    end

    task emit_cycle_json();
        if (!first_entry) begin
            $fdisplay(fd, ",");
        end
        first_entry = 0;

        $fwrite(fd, "  {\n");
        $fwrite(fd, "    \"cycle\": %0d,\n", cycle_cnt);
        $fwrite(fd, "    \"rst\": %0b,\n", rst);

        // CPU IF stage
        $fwrite(fd, "    \"if\": {\"pc\": \"0x%08x\", \"instr\": \"0x%08x\", \"stall\": %s},\n",
            core_dut.if_pc, core_dut.if_instr, (!core_dut.pc_write || core_dut.ex_branch_or_jump) ? "true" : "false");

        // CPU ID stage
        $fwrite(fd, "    \"id\": {\"pc\": \"0x%08x\", \"instr\": \"0x%08x\", \"stall\": %s, \"rs1\": %0d, \"rs2\": %0d, \"rd\": %0d, \"imm\": \"0x%08x\", \"rs1_val\": \"0x%08x\", \"rs2_val\": \"0x%08x\"},\n",
            core_dut.id_pc, core_dut.id_instr, (!core_dut.if_id_write) ? "true" : "false",
            core_dut.id_rs1, core_dut.id_rs2, core_dut.id_rd, core_dut.id_imm,
            core_dut.id_rs1_data, core_dut.id_rs2_data);

        // CPU EX stage
        $fwrite(fd, "    \"ex\": {\"pc\": \"0x%08x\", \"instr\": \"0x%08x\", \"alu_result\": \"0x%08x\", \"forward_a\": %0d, \"forward_b\": %0d},\n",
            core_dut.ex_pc, tb_ex_instr, core_dut.ex_alu_result,
            core_dut.forward_a, core_dut.forward_b);

        // CPU MEM stage
        $fwrite(fd, "    \"mem\": {\"pc\": \"0x%08x\", \"instr\": \"0x%08x\", \"addr\": \"0x%08x\", \"mem_read\": %s, \"mem_write\": %s, \"write_data\": \"0x%08x\", \"read_data\": \"0x%08x\", \"is_npu\": %s},\n",
            tb_mem_pc, tb_mem_instr, core_dut.ex_mem_alu_result,
            core_dut.ex_mem_mem_read ? "true" : "false",
            core_dut.ex_mem_mem_write ? "true" : "false",
            core_dut.dmem_store_data, core_dut.mem_dmem_read_data,
            core_dut.is_npu_addr ? "true" : "false");

        // CPU WB stage
        $fwrite(fd, "    \"wb\": {\"pc\": \"0x%08x\", \"instr\": \"0x%08x\", \"rd\": %0d, \"reg_write\": %s, \"write_data\": \"0x%08x\"},\n",
            tb_wb_pc, tb_wb_instr, core_dut.wb_rd, core_dut.wb_reg_write ? "true" : "false", core_dut.wb_write_data);

        // CPU Register file snapshot
        $fwrite(fd, "    \"regs\": [");
        for (int i = 0; i < 32; i++) begin
            $fwrite(fd, "\"0x%08x\"%s", core_dut.regfile.regs[i], (i == 31) ? "" : ", ");
        end
        $fwrite(fd, "],\n");

        // NPU Subsystem State
        $fwrite(fd, "    \"npu\": {\n");
        $fwrite(fd, "      \"state\": \"%s\",\n", (core_dut.npu_inst.state == 2'd0) ? "IDLE" : (core_dut.npu_inst.state == 2'd1) ? "CALC" : "DONE");
        $fwrite(fd, "      \"busy\": %s,\n", core_dut.npu_inst.busy ? "true" : "false");
        $fwrite(fd, "      \"done\": %s,\n", core_dut.npu_inst.done ? "true" : "false");
        $fwrite(fd, "      \"dim_m\": %0d,\n", core_dut.npu_inst.dim_m);
        $fwrite(fd, "      \"dim_k\": %0d,\n", core_dut.npu_inst.dim_k);
        $fwrite(fd, "      \"dim_n\": %0d,\n", core_dut.npu_inst.dim_n);
        $fwrite(fd, "      \"idx_i\": %0d,\n", core_dut.npu_inst.idx_i);
        $fwrite(fd, "      \"idx_j\": %0d,\n", core_dut.npu_inst.idx_j);
        $fwrite(fd, "      \"idx_k\": %0d,\n", core_dut.npu_inst.idx_k);
        $fwrite(fd, "      \"op_a\": %0d,\n", core_dut.npu_inst.op_a);
        $fwrite(fd, "      \"op_b\": %0d,\n", core_dut.npu_inst.op_b);
        $fwrite(fd, "      \"prod\": %0d,\n", core_dut.npu_inst.prod);
        $fwrite(fd, "      \"accum\": %0d,\n", core_dut.npu_inst.accum);
        $fwrite(fd, "      \"cycle_count\": %0d,\n", core_dut.npu_inst.cycle_count);
        $fwrite(fd, "      \"mmio_addr\": \"0x%08x\",\n", core_dut.ex_mem_alu_result);
        $fwrite(fd, "      \"mmio_we\": %s,\n", core_dut.npu_we ? "true" : "false");
        $fwrite(fd, "      \"mmio_re\": %s,\n", core_dut.npu_re ? "true" : "false");
        $fwrite(fd, "      \"mmio_wdata\": \"0x%08x\",\n", core_dut.dmem_store_data);
        $fwrite(fd, "      \"mmio_rdata\": \"0x%08x\",\n", core_dut.npu_read_data);

        // 4x4 subset of Matrix A, B, C for compact rendering
        $fwrite(fd, "      \"mat_a\": [");
        for (int r = 0; r < 4; r++) begin
            for (int c = 0; c < 4; c++) begin
                $fwrite(fd, "%0d%s", core_dut.npu_inst.mat_a_sram[r * 16 + c], (r == 3 && c == 3) ? "" : ", ");
            end
        end
        $fwrite(fd, "],\n");

        $fwrite(fd, "      \"mat_b\": [");
        for (int r = 0; r < 4; r++) begin
            for (int c = 0; c < 4; c++) begin
                $fwrite(fd, "%0d%s", core_dut.npu_inst.mat_b_sram[r * 16 + c], (r == 3 && c == 3) ? "" : ", ");
            end
        end
        $fwrite(fd, "],\n");

        $fwrite(fd, "      \"mat_c\": [");
        for (int r = 0; r < 4; r++) begin
            for (int c = 0; c < 4; c++) begin
                $fwrite(fd, "%0d%s", core_dut.npu_inst.mat_c_sram[r * 16 + c], (r == 3 && c == 3) ? "" : ", ");
            end
        end
        $fwrite(fd, "]\n");

        $fwrite(fd, "    }\n");
        $fwrite(fd, "  }");
    endtask

    initial begin
        string arg_val;
        if ($value$plusargs("MAX_CYCLES=%d", max_cycles)) begin
            $display("Running with MAX_CYCLES = %0d", max_cycles);
        end
        if ($value$plusargs("DUMP_FILE=%s", dump_file)) begin
            $display("Dumping telemetry to %s", dump_file);
        end

        fd = $fopen(dump_file, "w");
        if (fd == 0) begin
            $display("ERROR: Could not open %s for writing", dump_file);
            $finish(1);
        end

        $fwrite(fd, "{\n  \"cycles\": [\n");

        @(negedge clk);
        rst = 0;

        while (cycle_cnt < max_cycles) begin
            cycle_cnt++;
            emit_cycle_json();
            @(negedge clk);
            if (core_dut.id_instr == 32'h0000006f && core_dut.if_instr == 32'h0000006f && cycle_cnt > 45) begin
                // Self-loop terminated
                break;
            end
        end

        $fwrite(fd, "\n  ]\n}\n");
        $fclose(fd);
        $display("Telemetry dump complete: %0d cycles recorded in %s", cycle_cnt, dump_file);
        $finish(0);
    end

endmodule
