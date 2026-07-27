// Directed testbench for the AXI4-Lite wrapper (barycentric_axi).
//
// The underlying math is already verified bit-for-bit against a Python
// golden model by tb_barycentric.sv/compare.py -- this testbench instead
// exercises the AXI register interface itself: real AXI4-Lite write/read
// handshakes, the CTRL-strobe/STATUS-poll control flow, and byte-strobed
// partial writes. Expected outputs below are computed by hand from
// out = (1-u-v)*v0 + u*v1 + v*v2, chosen so results land on exact
// Q16.16 values (no truncation noise to account for).
module tb_barycentric_axi;
    import fixed_pkg::*;

    localparam int ADDR_W = 6;
    localparam int DATA_W = 32;

    logic clk = 1'b0;
    logic rst_n;
    always #5 clk = ~clk;  // 100 MHz

    logic [ADDR_W-1:0] s_axi_awaddr;
    logic              s_axi_awvalid;
    logic              s_axi_awready;
    logic [DATA_W-1:0] s_axi_wdata;
    logic [3:0]        s_axi_wstrb;
    logic              s_axi_wvalid;
    logic              s_axi_wready;
    logic [1:0]        s_axi_bresp;
    logic              s_axi_bvalid;
    logic              s_axi_bready;
    logic [ADDR_W-1:0] s_axi_araddr;
    logic              s_axi_arvalid;
    logic              s_axi_arready;
    logic [DATA_W-1:0] s_axi_rdata;
    logic [1:0]        s_axi_rresp;
    logic              s_axi_rvalid;
    logic              s_axi_rready;

    int errors = 0;

    barycentric_axi #(
        .C_S_AXI_ADDR_WIDTH(ADDR_W),
        .C_S_AXI_DATA_WIDTH(DATA_W)
    ) dut (.*);

    // register byte offsets, matching barycentric_axi's map
    localparam logic [ADDR_W-1:0]
        A_V0X=6'h00, A_V0Y=6'h04, A_V0Z=6'h08,
        A_V1X=6'h0C, A_V1Y=6'h10, A_V1Z=6'h14,
        A_V2X=6'h18, A_V2Y=6'h1C, A_V2Z=6'h20,
        A_U=6'h24,   A_V=6'h28,
        A_CTRL=6'h2C, A_STATUS=6'h30,
        A_OUTX=6'h34, A_OUTY=6'h38, A_OUTZ=6'h3C;

    task automatic axi_write(input logic [ADDR_W-1:0] addr, input logic [31:0] data,
                              input logic [3:0] strb = 4'hF);
        @(posedge clk);
        s_axi_awaddr  <= addr;
        s_axi_awvalid <= 1'b1;
        s_axi_wdata   <= data;
        s_axi_wstrb   <= strb;
        s_axi_wvalid  <= 1'b1;
        s_axi_bready  <= 1'b1;
        do @(posedge clk); while (!(s_axi_awready && s_axi_wready));
        s_axi_awvalid <= 1'b0;
        s_axi_wvalid  <= 1'b0;
        do @(posedge clk); while (!s_axi_bvalid);
        s_axi_bready  <= 1'b0;
    endtask

    task automatic axi_read(input logic [ADDR_W-1:0] addr, output logic [31:0] data);
        @(posedge clk);
        s_axi_araddr  <= addr;
        s_axi_arvalid <= 1'b1;
        s_axi_rready  <= 1'b1;
        do @(posedge clk); while (!s_axi_arready);
        s_axi_arvalid <= 1'b0;
        do @(posedge clk); while (!s_axi_rvalid);
        data = s_axi_rdata;
        s_axi_rready  <= 1'b0;
    endtask

    task automatic check(input string what, input logic [31:0] got, input logic [31:0] want);
        if (got !== want) begin
            $display("ERROR: %s: got 0x%08h, want 0x%08h", what, got, want);
            errors++;
        end else begin
            $display("OK: %s = 0x%08h", what, got);
        end
    endtask

    task automatic run_point(
        input fixed_t v0x, v0y, v0z, v1x, v1y, v1z, v2x, v2y, v2z, u, v,
        input fixed_t exp_x, exp_y, exp_z, input string label
    );
        logic [31:0] status, rd;
        axi_write(A_V0X, v0x); axi_write(A_V0Y, v0y); axi_write(A_V0Z, v0z);
        axi_write(A_V1X, v1x); axi_write(A_V1Y, v1y); axi_write(A_V1Z, v1z);
        axi_write(A_V2X, v2x); axi_write(A_V2Y, v2y); axi_write(A_V2Z, v2z);
        axi_write(A_U, u); axi_write(A_V, v);
        axi_write(A_CTRL, 32'h1);

        status = 32'h0;
        do axi_read(A_STATUS, status); while (status[0] !== 1'b1);

        axi_read(A_OUTX, rd); check({label, " OUTX"}, rd, exp_x);
        axi_read(A_OUTY, rd); check({label, " OUTY"}, rd, exp_y);
        axi_read(A_OUTZ, rd); check({label, " OUTZ"}, rd, exp_z);
    endtask

    initial begin
        rst_n = 1'b0;
        s_axi_awaddr=0; s_axi_awvalid=0; s_axi_wdata=0; s_axi_wstrb=0; s_axi_wvalid=0;
        s_axi_bready=0; s_axi_araddr=0; s_axi_arvalid=0; s_axi_rready=0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // Vector 1: v0=(0,0,0) v1=(10,0,0) v2=(0,10,0), u=v=0.25 -> (2.5,2.5,0)
        run_point(
            32'h00000000, 32'h00000000, 32'h00000000,
            32'h000A0000, 32'h00000000, 32'h00000000,
            32'h00000000, 32'h000A0000, 32'h00000000,
            32'h00004000, 32'h00004000,
            32'h00028000, 32'h00028000, 32'h00000000,
            "vec1"
        );

        // Vector 2: v0=(1,2,3) v1=(4,5,6) v2=(7,8,9), u=0.5 v=0.25 -> (4,5,6) exactly
        run_point(
            32'h00010000, 32'h00020000, 32'h00030000,
            32'h00040000, 32'h00050000, 32'h00060000,
            32'h00070000, 32'h00080000, 32'h00090000,
            32'h00008000, 32'h00004000,
            32'h00040000, 32'h00050000, 32'h00060000,
            "vec2"
        );

        // Byte-strobe check: V0X currently 0x00010000 (from vec2). Overwrite
        // only its low byte via wstrb=4'b0001, leaving the other 3 bytes
        // untouched, then read back the whole word.
        begin
            logic [31:0] rd;
            axi_write(A_V0X, 32'h000000AB, 4'b0001);
            axi_read(A_V0X, rd);
            check("byte-strobe V0X", rd, 32'h000100AB);
        end

        if (errors == 0) $display("TB_DONE: ALL PASS");
        else              $display("TB_DONE: %0d FAILURES", errors);
        $finish;
    end
endmodule : tb_barycentric_axi
