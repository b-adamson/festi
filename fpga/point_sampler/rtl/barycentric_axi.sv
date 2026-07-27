// AXI4-Lite peripheral wrapping the barycentric core, for wiring to a Zynq
// PS over a proper AXI interconnect (replacing the VIO/JTAG debug path in
// barycentric_vio_top.sv with something an embedded CPU can talk to over
// memory-mapped I/O).
//
// Register map (word-aligned, 32-bit AXI4-Lite):
//   0x00 V0X   0x04 V0Y   0x08 V0Z   (read/write, Q16.16)
//   0x0C V1X   0x10 V1Y   0x14 V1Z   (read/write, Q16.16)
//   0x18 V2X   0x1C V2Y   0x20 V2Z   (read/write, Q16.16)
//   0x24 U     0x28 V                (read/write, Q16.16)
//   0x2C CTRL  bit0: write 1 to latch the registers above into the core
//              and start a new computation (self-clearing -- reads back 0).
//   0x30 STATUS bit0: DONE -- set 3 cycles after CTRL is strobed, cleared
//              by the next strobe. Poll this before reading the outputs.
//   0x34 OUTX  0x38 OUTY  0x3C OUTZ  (read-only, Q16.16, valid once DONE=1)
//
// Software flow: write the 11 input registers, write CTRL=1, poll STATUS
// until DONE=1, read OUTX/OUTY/OUTZ. The core's own latency (3 cycles) is
// negligible next to any real AXI round-trip, so there's no need for the
// core to expose backpressure here -- one operation at a time is enough.
module barycentric_axi
    import fixed_pkg::*;
#(
    parameter int C_S_AXI_ADDR_WIDTH = 6,
    parameter int C_S_AXI_DATA_WIDTH = 32
)
(
    input  logic clk,
    input  logic rst_n,

    input  logic [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  logic                          s_axi_awvalid,
    output logic                          s_axi_awready,

    input  logic [C_S_AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input  logic [C_S_AXI_DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  logic                          s_axi_wvalid,
    output logic                          s_axi_wready,

    output logic [1:0] s_axi_bresp,
    output logic       s_axi_bvalid,
    input  logic       s_axi_bready,

    input  logic [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  logic                          s_axi_arvalid,
    output logic                          s_axi_arready,

    output logic [C_S_AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output logic [1:0]                    s_axi_rresp,
    output logic                          s_axi_rvalid,
    input  logic                          s_axi_rready
);

    localparam int NUM_REGS = 16;  // covers offsets 0x00-0x3C at 4B stride
    localparam int REG_V0X = 0,  REG_V0Y = 1,  REG_V0Z = 2;
    localparam int REG_V1X = 3,  REG_V1Y = 4,  REG_V1Z = 5;
    localparam int REG_V2X = 6,  REG_V2Y = 7,  REG_V2Z = 8;
    localparam int REG_U   = 9,  REG_V   = 10;
    localparam int REG_CTRL   = 11;
    localparam int REG_STATUS = 12;
    localparam int REG_OUTX = 13, REG_OUTY = 14, REG_OUTZ = 15;

    // ---- Write-address / write-data channel (accepts either order) ----
    logic aw_en;
    logic [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_awready <= 1'b0;
            aw_en         <= 1'b1;
        end else if (~s_axi_awready && s_axi_awvalid && s_axi_wvalid && aw_en) begin
            s_axi_awready <= 1'b1;
            aw_en         <= 1'b0;
        end else if (s_axi_bvalid && s_axi_bready) begin
            s_axi_awready <= 1'b0;
            aw_en         <= 1'b1;
        end else begin
            s_axi_awready <= 1'b0;
        end
    end

    always_ff @(posedge clk) begin
        if (~s_axi_awready && s_axi_awvalid && s_axi_wvalid && aw_en)
            axi_awaddr <= s_axi_awaddr;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) s_axi_wready <= 1'b0;
        else        s_axi_wready <= (~s_axi_wready && s_axi_wvalid && s_axi_awvalid && aw_en);
    end

    // ---- Write response channel ----
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_bvalid <= 1'b0;
            s_axi_bresp  <= 2'b00;
        end else if (s_axi_awready && s_axi_awvalid && ~s_axi_bvalid &&
                     s_axi_wready && s_axi_wvalid) begin
            s_axi_bvalid <= 1'b1;
            s_axi_bresp  <= 2'b00;  // OKAY
        end else if (s_axi_bvalid && s_axi_bready) begin
            s_axi_bvalid <= 1'b0;
        end
    end

    wire do_write = s_axi_wready && s_axi_wvalid && s_axi_awready && s_axi_awvalid;

    // ---- Read-address channel ----
    logic [C_S_AXI_ADDR_WIDTH-1:0] axi_araddr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_arready <= 1'b0;
            axi_araddr    <= '0;
        end else if (~s_axi_arready && s_axi_arvalid) begin
            s_axi_arready <= 1'b1;
            axi_araddr    <= s_axi_araddr;
        end else begin
            s_axi_arready <= 1'b0;
        end
    end

    // ---- Read-data channel ----
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rresp  <= 2'b00;
        end else if (s_axi_arready && s_axi_arvalid && ~s_axi_rvalid) begin
            s_axi_rvalid <= 1'b1;
            s_axi_rresp  <= 2'b00;
        end else if (s_axi_rvalid && s_axi_rready) begin
            s_axi_rvalid <= 1'b0;
        end
    end

    // ---- Register file + core wiring ----
    fixed_t v0x_reg, v0y_reg, v0z_reg;
    fixed_t v1x_reg, v1y_reg, v1z_reg;
    fixed_t v2x_reg, v2y_reg, v2z_reg;
    fixed_t u_reg, v_reg;
    fixed_t outx_reg, outy_reg, outz_reg;
    logic   done_reg;
    logic   start_pulse;

    logic   core_valid_out;
    fixed_t core_outx, core_outy, core_outz;

    barycentric core (
        .clk       (clk),
        .rst_n     (rst_n),
        .valid_in  (start_pulse),
        .v0x (v0x_reg), .v0y (v0y_reg), .v0z (v0z_reg),
        .v1x (v1x_reg), .v1y (v1y_reg), .v1z (v1z_reg),
        .v2x (v2x_reg), .v2y (v2y_reg), .v2z (v2z_reg),
        .u (u_reg), .v (v_reg),
        .valid_out (core_valid_out),
        .outx (core_outx), .outy (core_outy), .outz (core_outz)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v0x_reg <= '0; v0y_reg <= '0; v0z_reg <= '0;
            v1x_reg <= '0; v1y_reg <= '0; v1z_reg <= '0;
            v2x_reg <= '0; v2y_reg <= '0; v2z_reg <= '0;
            u_reg   <= '0; v_reg   <= '0;
            outx_reg <= '0; outy_reg <= '0; outz_reg <= '0;
            done_reg    <= 1'b0;
            start_pulse <= 1'b0;
        end else begin
            start_pulse <= 1'b0;  // one-cycle pulse, default low each cycle

            if (do_write) begin
                automatic int idx = int'(axi_awaddr[C_S_AXI_ADDR_WIDTH-1:2]);

                unique case (idx)
                    REG_V0X: for (int b=0;b<4;b++) if (s_axi_wstrb[b]) v0x_reg[b*8+:8] <= s_axi_wdata[b*8+:8];
                    REG_V0Y: for (int b=0;b<4;b++) if (s_axi_wstrb[b]) v0y_reg[b*8+:8] <= s_axi_wdata[b*8+:8];
                    REG_V0Z: for (int b=0;b<4;b++) if (s_axi_wstrb[b]) v0z_reg[b*8+:8] <= s_axi_wdata[b*8+:8];
                    REG_V1X: for (int b=0;b<4;b++) if (s_axi_wstrb[b]) v1x_reg[b*8+:8] <= s_axi_wdata[b*8+:8];
                    REG_V1Y: for (int b=0;b<4;b++) if (s_axi_wstrb[b]) v1y_reg[b*8+:8] <= s_axi_wdata[b*8+:8];
                    REG_V1Z: for (int b=0;b<4;b++) if (s_axi_wstrb[b]) v1z_reg[b*8+:8] <= s_axi_wdata[b*8+:8];
                    REG_V2X: for (int b=0;b<4;b++) if (s_axi_wstrb[b]) v2x_reg[b*8+:8] <= s_axi_wdata[b*8+:8];
                    REG_V2Y: for (int b=0;b<4;b++) if (s_axi_wstrb[b]) v2y_reg[b*8+:8] <= s_axi_wdata[b*8+:8];
                    REG_V2Z: for (int b=0;b<4;b++) if (s_axi_wstrb[b]) v2z_reg[b*8+:8] <= s_axi_wdata[b*8+:8];
                    REG_U:   for (int b=0;b<4;b++) if (s_axi_wstrb[b]) u_reg[b*8+:8]   <= s_axi_wdata[b*8+:8];
                    REG_V:   for (int b=0;b<4;b++) if (s_axi_wstrb[b]) v_reg[b*8+:8]   <= s_axi_wdata[b*8+:8];
                    REG_CTRL: if (s_axi_wstrb[0] && s_axi_wdata[0]) begin
                        start_pulse <= 1'b1;
                        done_reg    <= 1'b0;
                    end
                    default: ;  // STATUS/OUTX/OUTY/OUTZ are read-only
                endcase
            end

            if (core_valid_out) begin
                outx_reg <= core_outx;
                outy_reg <= core_outy;
                outz_reg <= core_outz;
                done_reg <= 1'b1;
            end
        end
    end

    // ---- Read data mux ----
    logic [C_S_AXI_DATA_WIDTH-1:0] reg_data_out;
    always_comb begin
        unique case (int'(axi_araddr[C_S_AXI_ADDR_WIDTH-1:2]))
            REG_V0X: reg_data_out = v0x_reg;
            REG_V0Y: reg_data_out = v0y_reg;
            REG_V0Z: reg_data_out = v0z_reg;
            REG_V1X: reg_data_out = v1x_reg;
            REG_V1Y: reg_data_out = v1y_reg;
            REG_V1Z: reg_data_out = v1z_reg;
            REG_V2X: reg_data_out = v2x_reg;
            REG_V2Y: reg_data_out = v2y_reg;
            REG_V2Z: reg_data_out = v2z_reg;
            REG_U:   reg_data_out = u_reg;
            REG_V:   reg_data_out = v_reg;
            REG_CTRL:   reg_data_out = 32'b0;
            REG_STATUS: reg_data_out = {31'b0, done_reg};
            REG_OUTX: reg_data_out = outx_reg;
            REG_OUTY: reg_data_out = outy_reg;
            REG_OUTZ: reg_data_out = outz_reg;
            default:  reg_data_out = 32'b0;
        endcase
    end

    always_ff @(posedge clk) begin
        if (s_axi_arready && s_axi_arvalid && ~s_axi_rvalid)
            s_axi_rdata <= reg_data_out;
    end

endmodule : barycentric_axi
