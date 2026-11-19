`timescale 1ns/1ps
// Streams +in samples into the DDC and dumps the baseband I/Q (+out) and the
// NCO cos/sin (+nco). One sample per clock unless +gap introduces idle cycles.
module tb_ddc;
    parameter LUT_FILE = "build/sine_quarter.hex";
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg  [31:0]        phase_inc = 0;
    reg                in_valid = 0;
    reg  signed [15:0] in_data = 0;
    wire               out_valid, nco_valid;
    wire signed [15:0] out_i, out_q, nco_cos, nco_sin;

    ddc #(.LUT_FILE(LUT_FILE)) dut (.*);

    integer fi, fo, fn, r, v, n = 0, gap = 0;
    string in_file, out_file, nco_file;

    always @(posedge clk) if (rst_n) begin
        if (out_valid) $fwrite(fo, "%0d %0d\n", out_i, out_q);
        if (nco_valid) $fwrite(fn, "%0d %0d\n", nco_cos, nco_sin);
    end

    initial begin
        void'($value$plusargs("inc=%h", phase_inc));
        void'($value$plusargs("gap=%d", gap));
        if (!$value$plusargs("in=%s", in_file))   in_file = "build/in.txt";
        if (!$value$plusargs("out=%s", out_file)) out_file = "build/out.txt";
        if (!$value$plusargs("nco=%s", nco_file)) nco_file = "build/nco.txt";
        fi = $fopen(in_file, "r"); fo = $fopen(out_file, "w"); fn = $fopen(nco_file, "w");
        repeat (3) @(posedge clk);
        rst_n = 1;
        while ($fscanf(fi, "%d", v) == 1) begin
            while (gap > 0 && $urandom_range(0, 99) < gap) begin in_valid <= 0; @(posedge clk); end
            in_valid <= 1; in_data <= v;
            @(posedge clk);
            n = n + 1;
        end
        in_valid <= 0;
        repeat (10) @(posedge clk);
        $fclose(fo); $fclose(fn);
        $finish;
    end
endmodule
