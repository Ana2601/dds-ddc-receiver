// Digital down-converter (SDR receiver front end):
//
//   ADC samples --> x e^{-j w n} (NCO + quadrature mixer) --> CIC /R (I and Q) --> baseband I/Q
//
// A real input tone at f_nco + d appears at the output as a complex tone at +d,
// with the sample rate reduced by R. 16-bit datapath throughout.
module ddc #(
    parameter        LUT_FILE = "sine_quarter.hex",
    parameter integer N  = 4,
    parameter integer LR = 4
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire        [31:0] phase_inc,
    input  wire               in_valid,
    input  wire signed [15:0] in_data,

    output wire               out_valid,
    output wire signed [15:0] out_i,
    output wire signed [15:0] out_q,

    // NCO observation (for spectral-purity measurement)
    output wire signed [15:0] nco_cos,
    output wire signed [15:0] nco_sin,
    output reg                nco_valid
);
    nco #(.LUT_FILE(LUT_FILE)) u_nco (.clk(clk), .rst_n(rst_n), .en(in_valid), .phase_inc(phase_inc),
                                      .cos_o(nco_cos), .sin_o(nco_sin));

    reg signed [15:0] x_a;
    reg               v_a, v_b;
    reg signed [15:0] i_b, q_b;

    // Q1.15 x Q1.15, rounded back to 16 bits
    wire signed [31:0] pi = x_a * nco_cos;
    wire signed [31:0] pq = x_a * nco_sin;
    wire signed [31:0] ri = (pi + 32'sd16384) >>> 15;
    wire signed [31:0] rq = (pq + 32'sd16384) >>> 15;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_a <= 16'sd0; v_a <= 1'b0; v_b <= 1'b0; i_b <= 16'sd0; q_b <= 16'sd0; nco_valid <= 1'b0;
        end else begin
            v_a <= in_valid;
            nco_valid <= in_valid;
            if (in_valid) x_a <= in_data;
            v_b <= v_a;
            if (v_a) begin
                i_b <= ri[15:0];
                q_b <= -rq[15:0];                     // multiply by e^{-jwn}: Q = -x sin
            end
        end
    end

    cic_decimator #(.IW(16), .N(N), .LR(LR)) u_cic_i (.clk(clk), .rst_n(rst_n), .in_valid(v_b), .in_data(i_b),
                                                     .out_valid(out_valid), .out_data(out_i));
    wire q_valid_unused;                                // identical to out_valid (same control path)
    cic_decimator #(.IW(16), .N(N), .LR(LR)) u_cic_q (.clk(clk), .rst_n(rst_n), .in_valid(v_b), .in_data(q_b),
                                                     .out_valid(q_valid_unused), .out_data(out_q));
endmodule
