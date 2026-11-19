// Numerically controlled oscillator (DDS): 32-bit phase accumulator,
// 12-bit phase to amplitude through a 1024-entry quarter-wave sine ROM
// (quadrant symmetry gives the full circle), 16-bit signed cos/sin outputs.
// Output frequency = phase_inc / 2^32 * f_sample.
//
// Sample n uses phase n * phase_inc; outputs are registered (1 cycle latency).
module nco #(
    parameter LUT_FILE = "sine_quarter.hex"
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               en,
    input  wire        [31:0] phase_inc,
    output reg  signed [15:0] cos_o,
    output reg  signed [15:0] sin_o
);
    reg [15:0] lut [0:1023];
    initial $readmemh(LUT_FILE, lut);

    reg [31:0] phase;

    function automatic signed [15:0] sine(input [11:0] p);    // p = quadrant & 10-bit index
        reg [9:0] i;
        reg [15:0] v;
        begin
            i = p[11:10] == 2'd1 || p[11:10] == 2'd3 ? ~p[9:0] : p[9:0];
            v = lut[i];
            sine = p[11] ? -$signed(v) : $signed(v);
        end
    endfunction

    wire [11:0] ps = phase[31:20];
    wire [11:0] pc = phase[31:20] + 12'h400;                   // cos(x) = sin(x + pi/2)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= 32'd0; cos_o <= 16'sd0; sin_o <= 16'sd0;
        end else if (en) begin
            phase <= phase + phase_inc;
            cos_o <= sine(pc);
            sin_o <= sine(ps);
        end
    end
endmodule
