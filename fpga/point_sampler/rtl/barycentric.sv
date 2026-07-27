// Streaming barycentric point-on-triangle interpolator.
//
// This is the hardware form of the last line of festi's addRndInstance()
// (src/model.cpp): given a triangle (v0,v1,v2) and a barycentric sample
// (u,v), it computes
//
//     w   = 1 - u - v
//     out = w*v0 + u*v1 + v*v2
//
// One (v0,v1,v2,u,v) tuple is accepted per cycle on the input side; the
// corresponding result appears on the output side 3 cycles later, in
// issue order, with valid_out flagging live results. This is the core
// primitive festi's procedural instancing (buildings/random scatter) and
// a rasterizer's attribute interpolation both reduce to.
module barycentric
    import fixed_pkg::*;
(
    input  logic clk,
    input  logic rst_n,

    input  logic   valid_in,
    input  fixed_t v0x, v0y, v0z,
    input  fixed_t v1x, v1y, v1z,
    input  fixed_t v2x, v2y, v2z,
    input  fixed_t u,   v,

    output logic   valid_out,
    output fixed_t outx, outy, outz

);

    fixed_t v0x_s0, v0y_s0, v0z_s0;
    fixed_t v1x_s0, v1y_s0, v1z_s0;
    fixed_t v2x_s0, v2y_s0, v2z_s0;
    fixed_t w_s0, u_s0, v_s0;
    logic   valid_s0;

    fixed_t wv0x_s1, wv0y_s1, wv0z_s1;
    fixed_t uv1x_s1, uv1y_s1, uv1z_s1;
    fixed_t vv2x_s1, vv2y_s1, vv2z_s1;
    logic valid_s1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s0 <= 0;
            valid_s1 <= 0;
            valid_out <= 0;

            v0x_s0   <= 0;
            v0y_s0   <= 0;
            v0z_s0   <= 0;
            v1x_s0   <= 0;
            v1y_s0   <= 0;
            v1z_s0   <= 0;
            v2x_s0   <= 0;
            v2y_s0   <= 0;
            v2z_s0   <= 0;
            w_s0     <= 0;
            u_s0     <= 0;
            v_s0     <= 0;

            wv0x_s1  <= 0;
            wv0y_s1  <= 0;
            wv0z_s1  <= 0;
            uv1x_s1  <= 0;
            uv1y_s1  <= 0;
            uv1z_s1  <= 0;
            vv2x_s1  <= 0;
            vv2y_s1  <= 0;
            vv2z_s1  <= 0;

            outx     <= 0;
            outy     <= 0;
            outz     <= 0;

        end else begin
            valid_s0 <= valid_in;
            v0x_s0   <= v0x;
            v0y_s0   <= v0y;
            v0z_s0   <= v0z;
            v1x_s0   <= v1x;
            v1y_s0   <= v1y;
            v1z_s0   <= v1z;
            v2x_s0   <= v2x;
            v2y_s0   <= v2y;
            v2z_s0   <= v2z;
            w_s0     <= FIXED_ONE - u - v;
            u_s0     <= u;
            v_s0     <= v;

            valid_s1 <= valid_s0;
            wv0x_s1  <= fx_mul(w_s0, v0x_s0);
            wv0y_s1  <= fx_mul(w_s0, v0y_s0);
            wv0z_s1  <= fx_mul(w_s0, v0z_s0);
            uv1x_s1  <= fx_mul(u_s0, v1x_s0);
            uv1y_s1  <= fx_mul(u_s0, v1y_s0);
            uv1z_s1  <= fx_mul(u_s0, v1z_s0);
            vv2x_s1  <= fx_mul(v_s0, v2x_s0);
            vv2y_s1  <= fx_mul(v_s0, v2y_s0);
            vv2z_s1  <= fx_mul(v_s0, v2z_s0);

            outx     <= wv0x_s1 + uv1x_s1 + vv2x_s1;
            outy     <= wv0y_s1 + uv1y_s1 + vv2y_s1;
            outz     <= wv0z_s1 + uv1z_s1 + vv2z_s1;

            valid_out <= valid_s1;
        end
    end

endmodule : barycentric
