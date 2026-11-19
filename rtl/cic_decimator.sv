// N-stage CIC decimator (Hogenauer), decimation R, differential delay 1.
// Register width W = IW + N*log2(R); two's-complement wrap-around in the
// integrators is intentional and exact (the combs undo it).
// Output = sum / R^N  (arithmetic shift by N*log2(R)), so DC gain is 1.
module cic_decimator #(
    parameter integer IW = 16,
    parameter integer N  = 4,
    parameter integer LR = 4                   // log2(R)
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 in_valid,
    input  wire signed [IW-1:0] in_data,
    output reg                  out_valid,
    output reg  signed [IW-1:0] out_data
);
    localparam integer W = IW + N * LR;

    reg signed [W-1:0] integ [0:N-1];
    reg signed [W-1:0] comb_d [0:N-1];          // comb delay elements
    reg        [LR-1:0] phase;

    // comb chain is combinational on the decimated integrator output
    reg signed [W-1:0] c [0:N];
    integer k;
    always @* begin
        c[0] = integ[N-1];
        for (k = 0; k < N; k = k + 1) c[k+1] = c[k] - comb_d[k];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (k = 0; k < N; k = k + 1) begin integ[k] <= {W{1'b0}}; comb_d[k] <= {W{1'b0}}; end
            phase <= {LR{1'b0}}; out_valid <= 1'b0; out_data <= {IW{1'b0}};
        end else begin
            out_valid <= 1'b0;
            if (in_valid) begin
                integ[0] <= integ[0] + {{(W-IW){in_data[IW-1]}}, in_data};
                for (k = 1; k < N; k = k + 1) integ[k] <= integ[k] + integ[k-1];
                phase <= phase + 1'b1;
                if (phase == {LR{1'b1}}) begin            // every R-th input: one output sample
                    for (k = 0; k < N; k = k + 1) comb_d[k] <= c[k];
                    out_valid <= 1'b1;
                    out_data  <= c[N] >>> (N * LR);
                end
            end
        end
    end
endmodule
