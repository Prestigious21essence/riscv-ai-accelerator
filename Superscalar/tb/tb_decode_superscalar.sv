// =============================================================================
// Testbench: tb_decode_superscalar
// Description: Comprehensive self-checking verification for control_superscalar
//              and imm_gen_superscalar.
//              Verifies:
//              1. Dual decoding of R-type and I-type instructions
//              2. Load and Store decoding and MemClass assignment
//              3. Custom-0 NPU instructions (load_a, load_b, store_c)
//              4. Branch and Jump decoding
//              5. Upper immediate decoding (LUI, AUIPC)
//              6. Parallel immediate generation across all formats (I, S, B, U, J)
// =============================================================================

`timescale 1ns/1ps

module tb_decode_superscalar;
    logic [31:0] slot0_instr, slot1_instr;

    // Slot 0 Control Signals
    logic [6:0]  slot0_opcode;
    logic [2:0]  slot0_funct3;
    logic [6:0]  slot0_funct7;
    logic [4:0]  slot0_rd, slot0_rs1, slot0_rs2;
    logic        slot0_uses_rs1, slot0_uses_rs2;
    logic        slot0_reg_write, slot0_mem_read, slot0_mem_write, slot0_mem_to_reg, slot0_alu_src;
    logic        slot0_branch, slot0_lui, slot0_jal, slot0_jalr, slot0_auipc;
    logic [3:0]  slot0_alu_op;
    logic [1:0]  slot0_mem_class;
    logic        slot0_is_npu_op;

    // Slot 1 Control Signals
    logic [6:0]  slot1_opcode;
    logic [2:0]  slot1_funct3;
    logic [6:0]  slot1_funct7;
    logic [4:0]  slot1_rd, slot1_rs1, slot1_rs2;
    logic        slot1_uses_rs1, slot1_uses_rs2;
    logic        slot1_reg_write, slot1_mem_read, slot1_mem_write, slot1_mem_to_reg, slot1_alu_src;
    logic        slot1_branch, slot1_lui, slot1_jal, slot1_jalr, slot1_auipc;
    logic [3:0]  slot1_alu_op;
    logic [1:0]  slot1_mem_class;
    logic        slot1_is_npu_op;

    // Immediates
    logic [31:0] slot0_imm, slot1_imm;

    int errors = 0;

    control_superscalar ctrl_dut (
        .slot0_instr(slot0_instr), .slot0_opcode(slot0_opcode), .slot0_funct3(slot0_funct3),
        .slot0_funct7(slot0_funct7), .slot0_rd(slot0_rd), .slot0_rs1(slot0_rs1), .slot0_rs2(slot0_rs2),
        .slot0_uses_rs1(slot0_uses_rs1), .slot0_uses_rs2(slot0_uses_rs2),
        .slot0_reg_write(slot0_reg_write), .slot0_mem_read(slot0_mem_read),
        .slot0_mem_write(slot0_mem_write), .slot0_mem_to_reg(slot0_mem_to_reg),
        .slot0_alu_src(slot0_alu_src), .slot0_branch(slot0_branch),
        .slot0_lui(slot0_lui), .slot0_jal(slot0_jal), .slot0_jalr(slot0_jalr),
        .slot0_auipc(slot0_auipc), .slot0_alu_op(slot0_alu_op),
        .slot0_mem_class(slot0_mem_class), .slot0_is_npu_op(slot0_is_npu_op),

        .slot1_instr(slot1_instr), .slot1_opcode(slot1_opcode), .slot1_funct3(slot1_funct3),
        .slot1_funct7(slot1_funct7), .slot1_rd(slot1_rd), .slot1_rs1(slot1_rs1), .slot1_rs2(slot1_rs2),
        .slot1_uses_rs1(slot1_uses_rs1), .slot1_uses_rs2(slot1_uses_rs2),
        .slot1_reg_write(slot1_reg_write), .slot1_mem_read(slot1_mem_read),
        .slot1_mem_write(slot1_mem_write), .slot1_mem_to_reg(slot1_mem_to_reg),
        .slot1_alu_src(slot1_alu_src), .slot1_branch(slot1_branch),
        .slot1_lui(slot1_lui), .slot1_jal(slot1_jal), .slot1_jalr(slot1_jalr),
        .slot1_auipc(slot1_auipc), .slot1_alu_op(slot1_alu_op),
        .slot1_mem_class(slot1_mem_class), .slot1_is_npu_op(slot1_is_npu_op)
    );

    imm_gen_superscalar imm_dut (
        .slot0_instr(slot0_instr), .slot0_imm(slot0_imm),
        .slot1_instr(slot1_instr), .slot1_imm(slot1_imm)
    );

    task check(string name, logic condition);
        if (!condition) begin
            $display("FAIL: %s", name);
            errors++;
        end else begin
            $display("PASS: %s", name);
        end
    endtask

    initial begin
        $display("\n=======================================================");
        $display("STARTING SUPERSCALAR DECODE & IMM_GEN TESTBENCH");
        $display("=======================================================\n");

        // ---------------------------------------------------------------------
        // Test 1: Slot 0 = ADD x3, x1, x2 | Slot 1 = ADDI x4, x3, -16
        // ---------------------------------------------------------------------
        slot0_instr = 32'h002081B3; // add x3, x1, x2 (rd=3, rs1=1, rs2=2)
        slot1_instr = 32'hFF018213; // addi x4, x3, -16 (rd=4, rs1=3, imm=-16)
        #1;
        check("Test 1a: Slot 0 ADD decoded correctly",
              slot0_reg_write && !slot0_alu_src && (slot0_alu_op == 4'b0000) &&
              (slot0_rd == 5'd3) && (slot0_rs1 == 5'd1) && (slot0_rs2 == 5'd2) &&
              slot0_uses_rs1 && slot0_uses_rs2 && (slot0_mem_class == 2'b00));

        check("Test 1b: Slot 1 ADDI decoded correctly",
              slot1_reg_write && slot1_alu_src && (slot1_alu_op == 4'b0000) &&
              (slot1_rd == 5'd4) && (slot1_rs1 == 5'd3) &&
              slot1_uses_rs1 && !slot1_uses_rs2 && (slot1_mem_class == 2'b00));

        check("Test 1c: Slot 1 negative immediate sign-extended (-16)",
              $signed(slot1_imm) == -16);

        // ---------------------------------------------------------------------
        // Test 2: Slot 0 = LW x5, 8(x1) | Slot 1 = SW x6, 12(x2)
        // ---------------------------------------------------------------------
        slot0_instr = 32'h0080A283; // lw x5, 8(x1)
        slot1_instr = 32'h00612623; // sw x6, 12(x2)
        #1;
        check("Test 2a: Slot 0 LW sets mem_read and mem_to_reg",
              slot0_reg_write && slot0_mem_read && slot0_mem_to_reg && slot0_alu_src &&
              (slot0_rd == 5'd5) && (slot0_rs1 == 5'd1) && (slot0_imm == 32'd8));

        check("Test 2b: Slot 1 SW sets mem_write and MEM_STORE class",
              !slot1_reg_write && slot1_mem_write && slot1_alu_src &&
              (slot1_rs1 == 5'd2) && (slot1_rs2 == 5'd6) && (slot1_mem_class == 2'b01) &&
              (slot1_imm == 32'd12));

        // ---------------------------------------------------------------------
        // Test 3: Custom-0 NPU Instructions: load_a (Bank A) & load_b (Bank B)
        // ---------------------------------------------------------------------
        slot0_instr = 32'h0005800B; // custom-0 funct3=0 (load_a rs1=x11)
        slot1_instr = 32'h0006100B; // custom-0 funct3=1 (load_b rs1=x12)
        #1;
        check("Test 3a: Slot 0 NPU load_a assigned MEM_BANK_A (2'b10)",
              slot0_is_npu_op && (slot0_mem_class == 2'b10) && slot0_uses_rs1 && (slot0_rs1 == 5'd11));

        check("Test 3b: Slot 1 NPU load_b assigned MEM_BANK_B (2'b11)",
              slot1_is_npu_op && (slot1_mem_class == 2'b11) && slot1_uses_rs1 && (slot1_rs1 == 5'd12));

        // ---------------------------------------------------------------------
        // Test 4: Custom-0 NPU store_c (MEM_STORE)
        // ---------------------------------------------------------------------
        slot0_instr = 32'h00C5A00B; // custom-0 funct3=2 (store_c rs1=x11, rs2=x12)
        slot1_instr = 32'h00000013; // NOP
        #1;
        check("Test 4: NPU store_c assigned MEM_STORE class (2'b01) and uses rs1 & rs2",
              slot0_is_npu_op && (slot0_mem_class == 2'b01) && slot0_uses_rs1 && slot0_uses_rs2);

        // ---------------------------------------------------------------------
        // Test 5: Branches & Jumps
        // ---------------------------------------------------------------------
        slot0_instr = 32'h04208463; // beq x1, x2, 72 (B-type)
        slot1_instr = 32'h064000EF; // jal x1, 100 (J-type)
        #1;
        check("Test 5a: Slot 0 BEQ decoded as branch with B-imm = 72",
              slot0_branch && !slot0_reg_write && (slot0_alu_op == 4'b0001) &&
              ($signed(slot0_imm) == 72));

        check("Test 5b: Slot 1 JAL decoded as jump with J-imm = 100",
              slot1_jal && slot1_reg_write && (slot1_rd == 5'd1) &&
              ($signed(slot1_imm) == 100));

        // ---------------------------------------------------------------------
        // Test 6: Upper Immediates (LUI, AUIPC)
        // ---------------------------------------------------------------------
        slot0_instr = 32'h123450B7; // lui x1, 0x12345
        slot1_instr = 32'h54321117; // auipc x2, 0x54321
        #1;
        check("Test 6a: LUI sets lui flag and shifts 12 bits",
              slot0_lui && slot0_reg_write && (slot0_imm == 32'h1234_5000));

        check("Test 6b: AUIPC sets auipc flag and shifts 12 bits",
              slot1_auipc && slot1_reg_write && (slot1_imm == 32'h5432_1000));

        // ---------------------------------------------------------------------
        // Final Summary
        // ---------------------------------------------------------------------
        if (errors == 0) begin
            $display("\n=======================================================");
            $display("ALL DECODE & IMM_GEN CHECKS PASSED (0 ERRORS)");
            $display("=======================================================\n");
        end else begin
            $display("\nFAILED: %0d errors detected in decode testbench.\n", errors);
        end
        $finish;
    end
endmodule

