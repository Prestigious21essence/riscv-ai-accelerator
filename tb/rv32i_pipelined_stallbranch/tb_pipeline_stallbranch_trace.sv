`timescale 1ns/1ps

module tb_pipeline_stallbranch_trace #(
    parameter MEM_WORDS = 256
);
    logic clk = 0;
    logic rst = 1;

    rv32i_pipeline_stallbranch_core #(.MEM_WORDS(MEM_WORDS)) core_dut (
        .clk(clk),
        .rst(rst)
    );

    always #5 clk = ~clk;

    // Shadow pipeline registers to track instructions and PCs through EX, MEM, WB
    logic [31:0] tb_ex_instr,  tb_ex_pc;
    logic [31:0] tb_mem_instr, tb_mem_pc;
    logic [31:0] tb_wb_instr,  tb_wb_pc;

    int cycle_cnt = 0;
    int max_cycles = 45;
    string hex_file = "";
    string dump_file = "cycle_dump.json";
    int fd;
    bit first_entry = 1;
    int drain_cycles = 0;

    always_ff @(posedge clk) begin
        if (rst) begin
            tb_ex_instr  <= 32'h00000013; // RISC-V NOP
            tb_ex_pc     <= 32'b0;
            tb_mem_instr <= 32'h00000013;
            tb_mem_pc    <= 32'b0;
            tb_wb_instr  <= 32'h00000013;
            tb_wb_pc     <= 32'b0;
        end else begin
            if (core_dut.flush_id_ex) begin
                tb_ex_instr <= 32'h00000013; // Bubble/NOP inserted into EX
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

        // IF stage
        $fwrite(fd, "    \"if\": {\"pc\": \"0x%08x\", \"instr\": \"0x%08x\", \"stall\": %s},\n",
            core_dut.if_pc, core_dut.if_instr, (!core_dut.pc_write) ? "true" : "false");

        // ID stage
        $fwrite(fd, "    \"id\": {\"pc\": \"0x%08x\", \"instr\": \"0x%08x\", \"stall\": %s, \"rs1\": %0d, \"rs2\": %0d, \"rd\": %0d, \"imm\": \"0x%08x\", \"rs1_val\": \"0x%08x\", \"rs2_val\": \"0x%08x\", \"uses_rs1\": %s, \"uses_rs2\": %s},\n",
            core_dut.id_pc, core_dut.id_instr, (!core_dut.if_id_write) ? "true" : "false",
            core_dut.id_rs1, core_dut.id_rs2, core_dut.id_rd, core_dut.id_imm,
            core_dut.id_rs1_data, core_dut.id_rs2_data,
            core_dut.id_uses_rs1 ? "true" : "false", core_dut.id_uses_rs2 ? "true" : "false");

        // EX stage
        $fwrite(fd, "    \"ex\": {\"pc\": \"0x%08x\", \"instr\": \"0x%08x\", \"rs1\": %0d, \"rs2\": %0d, \"rd\": %0d, \"alu_a\": \"0x%08x\", \"alu_b\": \"0x%08x\", \"alu_result\": \"0x%08x\", \"forward_a\": %0d, \"forward_b\": %0d, \"forwarded_a\": \"0x%08x\", \"forwarded_b\": \"0x%08x\", \"branch\": %s, \"branch_taken\": %s, \"target_pc\": \"0x%08x\", \"redirect\": %s, \"flush\": %s},\n",
            core_dut.ex_pc, tb_ex_instr, core_dut.ex_rs1, core_dut.ex_rs2, core_dut.ex_rd,
            core_dut.alu_a, core_dut.alu_b, core_dut.ex_alu_result,
            core_dut.forward_a, core_dut.forward_b, core_dut.forwarded_a, core_dut.forwarded_b,
            core_dut.ex_branch ? "true" : "false", core_dut.ex_branch_taken ? "true" : "false",
            core_dut.ex_resolved_pc, core_dut.ex_branch_or_jump ? "true" : "false", core_dut.flush_id_ex ? "true" : "false");

        // MEM stage
        $fwrite(fd, "    \"mem\": {\"pc\": \"0x%08x\", \"instr\": \"0x%08x\", \"rd\": %0d, \"reg_write\": %s, \"alu_result\": \"0x%08x\", \"mem_read\": %s, \"mem_write\": %s, \"write_data\": \"0x%08x\", \"read_data\": \"0x%08x\"},\n",
            tb_mem_pc, tb_mem_instr, core_dut.ex_mem_rd, core_dut.ex_mem_reg_write ? "true" : "false",
            core_dut.ex_mem_alu_result, core_dut.ex_mem_mem_read ? "true" : "false",
            core_dut.ex_mem_mem_write ? "true" : "false", core_dut.dmem_store_data, core_dut.mem_dmem_read_data);

        // WB stage
        $fwrite(fd, "    \"wb\": {\"pc\": \"0x%08x\", \"instr\": \"0x%08x\", \"rd\": %0d, \"reg_write\": %s, \"write_data\": \"0x%08x\"},\n",
            tb_wb_pc, tb_wb_instr, core_dut.wb_rd, core_dut.wb_reg_write ? "true" : "false", core_dut.wb_write_data);

        // Hazard unit summary
        $fwrite(fd, "    \"hazards\": {\"load_use_stall\": %s, \"branch_flush\": %s, \"branch_stall\": %s, \"flush_if_id\": %s, \"flush_id_ex\": %s, \"forward_a\": %0d, \"forward_b\": %0d},\n",
            ((!core_dut.pc_write) && core_dut.flush_id_ex) ? "true" : "false",
            "false",
            (core_dut.id_branch_or_jump || core_dut.ex_branch_or_jump) ? "true" : "false",
            core_dut.flush_if_id ? "true" : "false",
            core_dut.flush_id_ex ? "true" : "false",
            core_dut.forward_a, core_dut.forward_b);

        // Register file snapshot
        $fwrite(fd, "    \"regs\": [");
        for (int i = 0; i < 32; i++) begin
            $fwrite(fd, "\"0x%08x\"%s", core_dut.regfile.regs[i], (i == 31) ? "" : ", ");
        end
        $fwrite(fd, "]\n");

        $fwrite(fd, "  }");
    endtask

    initial begin
        if ($value$plusargs("HEX=%s", hex_file)) begin
            $display("[TB_TRACE] Loading instruction memory from: %s", hex_file);
            $readmemh(hex_file, core_dut.imem.mem);
        end
        if ($value$plusargs("MAX_CYCLES=%d", max_cycles)) begin
            $display("[TB_TRACE] Max cycles configured to: %0d", max_cycles);
        end
        if ($value$plusargs("DUMP_FILE=%s", dump_file)) begin
            $display("[TB_TRACE] Output dump file: %s", dump_file);
        end

        fd = $fopen(dump_file, "w");
        if (fd == 0) begin
            $display("ERROR: Failed to open %s for writing", dump_file);
            $finish;
        end
        $fdisplay(fd, "[");

        @(negedge clk);
        rst = 0;

        while (cycle_cnt < max_cycles) begin
            @(negedge clk);
            cycle_cnt++;
            emit_cycle_json();

            // Early termination check on self-loop jal x0, 0 or ebreak
            if (tb_wb_instr == 32'h0000006f || tb_wb_instr == 32'h00100073) begin
                drain_cycles++;
                if (drain_cycles >= 1) break;
            end
        end

        $fdisplay(fd, "\n]");
        $fclose(fd);
        $display("[TB_TRACE] Simulation finished. %0d cycles dumped to %s", cycle_cnt, dump_file);
        $finish;
    end
endmodule

