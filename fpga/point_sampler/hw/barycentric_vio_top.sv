// Top-level for live hardware bring-up of the barycentric core on the
// Kria K26 SOM (xck26), entirely over JTAG via a VIO probe -- no external
// pins, no board-specific pin constraints, so it doesn't matter whether
// this is sitting on a KV260 or KR260 carrier.
//
// Clock: STARTUPE3's CFGMCLK is the UltraScale+ post-configuration
// internal oscillator output. It's imprecise and not meant for real
// timing-critical designs, but since every signal here is read/written
// through JTAG (nothing is I/O-timing-critical), it's a genuinely free
// clock source that needs zero board knowledge -- worth knowing about
// even outside this project.
//
// The DUT is left free-running (valid_in tied high): since it has no
// internal state beyond the pipeline registers themselves, any new
// (v0,v1,v2,u,v) written via VIO simply appears at the output 3 cycles
// later. No need to pulse valid_in from software.
module barycentric_vio_top
    import fixed_pkg::*;
(
);

    wire clk;
    wire cfg_mclk;

    STARTUPE3 #(
        .PROG_USR("FALSE"),
        .SIM_CCLK_FREQ(0.0)
    ) startup_inst (
        .CFGCLK    (),
        .CFGMCLK   (cfg_mclk),
        .DI        (4'b0000),
        .DO        (),
        .DTS       (4'b1111),
        .EOS       (),
        .FCSBO     (1'b1),
        .FCSBTS    (1'b1),
        .GSR       (1'b0),
        .GTS       (1'b0),
        .KEYCLEARB (1'b1),
        .PACK      (1'b0),
        .PREQ      (),
        .USRCCLKO  (1'b0),
        .USRCCLKTS (1'b1),
        .USRDONEO  (1'b1),
        .USRDONETS (1'b1)
    );
    assign clk = cfg_mclk;

    // Power-on reset: counts up from its FF init value and never resets
    // again. No external reset pin needed.
    logic [3:0] rst_cnt = 4'h0;
    logic       rst_n;
    always_ff @(posedge clk) begin
        if (rst_cnt != 4'hF) rst_cnt <= rst_cnt + 4'h1;
    end
    assign rst_n = (rst_cnt == 4'hF);

    // VIO probe_out -> DUT inputs (Q16.16 fixed-point, written from
    // Vivado Hardware Manager / write_hw_vio)
    fixed_t v0x, v0y, v0z;
    fixed_t v1x, v1y, v1z;
    fixed_t v2x, v2y, v2z;
    fixed_t u, v;

    // DUT outputs -> VIO probe_in (read back with read_hw_vio)
    logic   dut_valid_out;
    fixed_t dut_outx, dut_outy, dut_outz;

    vio_0 vio_inst (
        .clk       (clk),

        .probe_in0 (dut_valid_out),
        .probe_in1 (dut_outx),
        .probe_in2 (dut_outy),
        .probe_in3 (dut_outz),

        .probe_out0  (v0x),
        .probe_out1  (v0y),
        .probe_out2  (v0z),
        .probe_out3  (v1x),
        .probe_out4  (v1y),
        .probe_out5  (v1z),
        .probe_out6  (v2x),
        .probe_out7  (v2y),
        .probe_out8  (v2z),
        .probe_out9  (u),
        .probe_out10 (v)
    );

    barycentric dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .valid_in  (1'b1),
        .v0x (v0x), .v0y (v0y), .v0z (v0z),
        .v1x (v1x), .v1y (v1y), .v1z (v1z),
        .v2x (v2x), .v2y (v2y), .v2z (v2z),
        .u (u), .v (v),
        .valid_out (dut_valid_out),
        .outx (dut_outx), .outy (dut_outy), .outz (dut_outz)
    );

endmodule : barycentric_vio_top
