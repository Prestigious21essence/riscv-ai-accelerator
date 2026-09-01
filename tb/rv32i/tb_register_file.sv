`timescale 1ns/1ps

module tb_register_file;
    logic        clk = 0;
    logic        we;
    logic [4:0]  rs1_addr, rs2_addr, rd_addr;
    logic [31:0] rd_data;
    logic [31:0] rs1_data, rs2_data;

    int errors = 0;

    register_file dut (
        .clk(clk), .we(we),
        .rs1_addr(rs1_addr), .rs2_addr(rs2_addr), .rd_addr(rd_addr),
        .rd_data(rd_data),
        .rs1_data(rs1_data), .rs2_data(rs2_data)
    );

    always #5 clk = ~clk;

    task check(string name, logic [31:0] actual, logic [31:0] expected);
        if (actual !== expected) begin
            $display("FAIL: %s -- expected %0d, got %0d", name, expected, actual);
            errors++;
        end else begin
            $display("PASS: %s", name);
        end
    endtask

    initial begin
        we = 0; rs1_addr = 0; rs2_addr = 0; rd_addr = 0; rd_data = 0;
	
	$dumpfile("dump.vcd");
	$dumpvars(0, tb_register_file);	

        // Drive inputs on negedge so they're stable before the next posedge
        @(negedge clk);
        we = 1; rd_addr = 5'd0; rd_data = 32'hDEADBEEF;
        @(posedge clk);  // DUT samples here

        @(negedge clk);
        rs1_addr = 5'd0;
        #1 check("x0 stays zero after write attempt", rs1_data, 32'd0);

        @(negedge clk);
        we = 1; rd_addr = 5'd5; rd_data = 32'h12345678;
        @(posedge clk);  // DUT samples here -- write happens

        @(negedge clk);
        we = 0;
        rs1_addr = 5'd5;
        #1 check("write/read x5", rs1_data, 32'h12345678);

        if (errors == 0)
            $display("\nALL TESTS PASSED");
        else
            $display("\n%0d TEST(S) FAILED", errors);

        $finish;
    end
endmodule
