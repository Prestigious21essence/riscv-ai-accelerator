`timescale 1ns/1ps

module tb_singlecycle_trace #(
    parameter MEM_WORDS = 256
);
    logic clk = 0;
    logic rst = 1;

    rv32i_core #(.MEM_WORDS(MEM_WORDS)) core_dut (
        .clk(clk),
        .rst(rst)
    );

    always #5 clk = ~clk;

    int cycle_cnt = 0;
    int max_cycles = 25;
    string hex_file = "";
    string dump_file = "cycle_dump.json";
    int fd;
    bit first_entry = 1;
    int drain_cycles = 0;

    // Identify which registers are read by the current instruction
    logic id_uses_rs1, id_uses_rs2;
    assign id_uses_rs1 = (core_dut.opcode == 7'b0110011) || // R-type
                         (core_dut.opcode == 7'b0010011) || // I-type ALU
                         (core_dut.opcode == 7'b0000011) || // Load
                         (core_dut.opcode == 7'b0100011) || // Store
                         (core_dut.opcode == 7'b1100011) || // Branch
                         (core_dut.opcode == 7'b1100111);   // JALR

    assign id_uses_rs2 = (core_dut.opcode == 7'b0110011) || // R-type
                         (core_dut.opcode == 7'b0100011) || // Store
                         (core_dut.opcode == 7'b1100011);   // Branch

    logic [31:0] target_pc;
    assign target_pc = core_dut.jalr ? core_dut.jalr_target :
                       (core_dut.branch_taken || core_dut.jal) ? (core_dut.pc_out + core_dut.imm) :
                       (core_dut.pc_out + 32'd4);

    task emit_cycle_json();
        if (!first_entry) begin
            $fdisplay(fd, ",");
        end
        first_entry = 0;

        $fwrite(fd, "  {\n");
        $fwrite(fd, "    \"cycle\": %0d,\n", cycle_cnt);
        $fwrite(fd, "    \"rst\": %0b,\n", rst);

        // IF stage
        $fwrite(fd, "    \"if\": {\"pc\": \"0x%08x\", \"instr\": \"0x%08x\", \"stall\": false},\n",
            core_dut.pc_out, core_dut.instr);

        // ID stage
        $fwrite(fd, "    \"id\": {\"pc\": \"0x%08x\", \"instr\": \"0x%08x\", \"stall\": false, \"rs1\": %0d, \"rs2\": %0d, \"rd\": %0d, \"imm\": \"0x%08x\", \"rs1_val\": \"0x%08x\", \"rs2_val\": \"0x%08x\", \"uses_rs1\": %s, \"uses_rs2\": %s},\n",
            core_dut.pc_out, core_dut.instr,
            core_dut.rs1, core_dut.rs2, core_dut.rd, core_dut.imm,
            core_dut.rs1_data, core_dut.rs2_data,
            id_uses_rs1 ? "true" : "false", id_uses_rs2 ? "true" : "false");

        // EX stage (No forwarding in single-cycle)
        $fwrite(fd, "    \"ex\": {\"pc\": \"0x%08x\", \"instr\": \"0x%08x\", \"rs1\": %0d, \"rs2\": %0d, \"rd\": %0d, \"alu_a\": \"0x%08x\", \"alu_b\": \"0x%08x\", \"alu_result\": \"0x%08x\", \"forward_a\": 0, \"forward_b\": 0, \"forwarded_a\": \"0x%08x\", \"forwarded_b\": \"0x%08x\", \"branch\": %s, \"branch_taken\": %s, \"target_pc\": \"0x%08x\", \"redirect\": %s, \"flush\": false},\n",
            core_dut.pc_out, core_dut.instr, core_dut.rs1, core_dut.rs2, core_dut.rd,
            core_dut.alu_a, core_dut.alu_b, core_dut.alu_result,
            core_dut.alu_a, core_dut.alu_b,
            core_dut.branch ? "true" : "false", core_dut.branch_taken ? "true" : "false",
            target_pc,
            (core_dut.branch_taken || core_dut.jal || core_dut.jalr) ? "true" : "false");

        // MEM stage
        $fwrite(fd, "    \"mem\": {\"pc\": \"0x%08x\", \"instr\": \"0x%08x\", \"rd\": %0d, \"reg_write\": %s, \"alu_result\": \"0x%08x\", \"mem_read\": %s, \"mem_write\": %s, \"write_data\": \"0x%08x\", \"read_data\": \"0x%08x\"},\n",
            core_dut.pc_out, core_dut.instr, core_dut.rd, core_dut.reg_write ? "true" : "false",
            core_dut.alu_result, core_dut.mem_read ? "true" : "false",
            core_dut.mem_write ? "true" : "false", core_dut.rs2_data, core_dut.read_data);

        // WB stage
        $fwrite(fd, "    \"wb\": {\"pc\": \"0x%08x\", \"instr\": \"0x%08x\", \"rd\": %0d, \"reg_write\": %s, \"write_data\": \"0x%08x\"},\n",
            core_dut.pc_out, core_dut.instr, core_dut.rd, core_dut.reg_write ? "true" : "false", core_dut.write_data);

        // Hazards (None in single-cycle)
        $fwrite(fd, "    \"hazards\": {\"load_use_stall\": false, \"branch_flush\": false, \"flush_if_id\": false, \"flush_id_ex\": false, \"forward_a\": 0, \"forward_b\": 0},\n");

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
            $display("[TB_SINGLECYCLE_TRACE] Loading instruction memory from: %s", hex_file);
            $readmemh(hex_file, core_dut.imem.mem);
        end
        if ($value$plusargs("MAX_CYCLES=%d", max_cycles)) begin
            $display("[TB_SINGLECYCLE_TRACE] Max cycles configured to: %0d", max_cycles);
        end
        if ($value$plusargs("DUMP_FILE=%s", dump_file)) begin
            $display("[TB_SINGLECYCLE_TRACE] Output dump file: %s", dump_file);
        end

        fd = $fopen(dump_file, "w");
        if (fd == 0) begin
            $display("ERROR: Failed to open %s for writing", dump_file);
            $finish;
        end
        $fdisplay(fd, "[");

        @(negedge clk);
        rst = 0;
        cycle_cnt++;
        emit_cycle_json();

        while (cycle_cnt < max_cycles) begin
            @(negedge clk);
            cycle_cnt++;
            emit_cycle_json();

            // Early termination check on self-loop jal x0, 0 or ebreak
            if (core_dut.instr == 32'h0000006f || core_dut.instr == 32'h00100073) begin
                break;
            end
        end

        $fdisplay(fd, "\n]");
        $fclose(fd);
        $display("[TB_SINGLECYCLE_TRACE] Simulation finished. %0d cycles dumped to %s", cycle_cnt, dump_file);
        $finish;
    end
endmodule
