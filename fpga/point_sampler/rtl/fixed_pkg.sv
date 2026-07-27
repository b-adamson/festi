// Q16.16 signed fixed-point conventions shared by the point_sampler core.
// Matches the precision festi's CPU path effectively works at (float, but
// world-space coordinates in these scenes stay well within +/-32768 with
// plenty of sub-unit precision to spare).
package fixed_pkg;

typedef logic signed [31:0] fixed_t;

localparam fixed_t FIXED_ONE = 1 << 16;

function automatic fixed_t fx_mul(input fixed_t a, input fixed_t b);
    logic signed [63:0] temp = a * b;
    return temp >>> 16;
endfunction

endpackage : fixed_pkg

