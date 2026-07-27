// File-driven testbench for the barycentric interpolation core.
//
// Reads vectors/vectors.txt (produced by scripts/gen_vectors.py, which
// mirrors the barycentric math from festi's addRndInstance() in plain
// Python), drives one triangle+sample per pass through the pipeline, and
// writes vectors/results.txt for scripts/compare.py to check against the
// golden model.
module tb_barycentric;
    import fixed_pkg::*;

    logic clk = 1'b0;
    logic rst_n;
    always #5 clk = ~clk;  // 100 MHz

    logic   valid_in;
    fixed_t v0x, v0y, v0z;
    fixed_t v1x, v1y, v1z;
    fixed_t v2x, v2y, v2z;
    fixed_t u, v;
    logic   valid_out;
    fixed_t outx, outy, outz;

    barycentric dut (.*);

    integer infile, outfile;
    integer n, i, rc;
    integer iv0x, iv0y, iv0z, iv1x, iv1y, iv1z, iv2x, iv2y, iv2z, iu, ivv;

    initial begin
        rst_n    = 1'b0;
        valid_in = 1'b0;
        v0x = '0; v0y = '0; v0z = '0;
        v1x = '0; v1y = '0; v1z = '0;
        v2x = '0; v2y = '0; v2z = '0;
        u   = '0; v   = '0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        infile = $fopen("vectors/vectors.txt", "r");
        if (infile == 0) begin
            $display("ERROR: could not open vectors/vectors.txt");
            $finish;
        end

        outfile = $fopen("vectors/results.txt", "w");
        if (outfile == 0) begin
            $display("ERROR: could not open vectors/results.txt for writing");
            $finish;
        end

        rc = $fscanf(infile, "%d", n);

        for (i = 0; i < n; i = i + 1) begin
            rc = $fscanf(infile, "%d %d %d %d %d %d %d %d %d %d %d",
                iv0x, iv0y, iv0z, iv1x, iv1y, iv1z, iv2x, iv2y, iv2z, iu, ivv);

            v0x = fixed_t'(iv0x); v0y = fixed_t'(iv0y); v0z = fixed_t'(iv0z);
            v1x = fixed_t'(iv1x); v1y = fixed_t'(iv1y); v1z = fixed_t'(iv1z);
            v2x = fixed_t'(iv2x); v2y = fixed_t'(iv2y); v2z = fixed_t'(iv2z);
            u   = fixed_t'(iu);   v   = fixed_t'(ivv);
            valid_in = 1'b1;

            @(posedge clk);  // stage 0 captures the sample
            valid_in = 1'b0;
            @(posedge clk);  // stage 1 captures the products
            @(posedge clk);  // stage 2 captures the sum -> valid_out high

            if (valid_out !== 1'b1) begin
                $display("ERROR: vector %0d did not produce a valid result", i);
            end
            $fwrite(outfile, "%0d %0d %0d\n", outx, outy, outz);
        end

        $fclose(infile);
        $fclose(outfile);
        $display("TB_DONE: wrote %0d results", n);
        $finish;
    end
endmodule : tb_barycentric
