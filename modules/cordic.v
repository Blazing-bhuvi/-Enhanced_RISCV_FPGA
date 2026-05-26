`timescale 1ns / 1ps
// Vectoring CORDIC implementation for Nexys A7-100T
module cordic #(
    parameter width = 18 // Internal width 18 to prevent overflow
)(
    input  wire clock,
    input  wire reset,
    input  wire signed [15:0] x_start,
    input  wire signed [15:0] y_start,
    output wire signed [31:0] angle_out // Replaced sine/cosine with Angle Output!
);

    // atan_table scaled to 32-bit (2^32 / 2pi) or similar fixed point
    wire signed [31:0] atan_table [0:15];
    assign atan_table[0]  = 32'h20000000; // 45 degrees
    assign atan_table[1]  = 32'h12E4051D; // 26.565
    assign atan_table[2]  = 32'h09FB385B; // 14.036
    assign atan_table[3]  = 32'h051111D4;
    assign atan_table[4]  = 32'h028B0D43;
    assign atan_table[5]  = 32'h0145D7E1;
    assign atan_table[6]  = 32'h00A2F61E;
    assign atan_table[7]  = 32'h00517C55;
    assign atan_table[8]  = 32'h0028BE53;
    assign atan_table[9]  = 32'h00145F2E;
    assign atan_table[10] = 32'h000A2F98;
    assign atan_table[11] = 32'h000517CC;
    assign atan_table[12] = 32'h00028BE6;
    assign atan_table[13] = 32'h000145F3;
    assign atan_table[14] = 32'h0000A2F9;
    assign atan_table[15] = 32'h0000517C;

    reg signed [width-1:0] x [0:16];
    reg signed [width-1:0] y [0:16];
    reg signed [31:0]      z [0:16];

    // Load inputs (Assuming Quadrant 1/4 for standard FIR DSP inputs)
    always @(posedge clock) begin
        if (reset) begin
            x[0] <= 0; y[0] <= 0; z[0] <= 0;
        end else begin
            x[0] <= {x_start, 2'b00}; // Pad for internal precision
            y[0] <= {y_start, 2'b00};
            z[0] <= 32'd0;            // In Vectoring, starting angle is ALWAYS 0
        end
    end

    // Pipeline stages
    genvar i;
    generate
        for (i=0; i < 16; i=i+1) begin: xyz_stage
            
            // THE FIX: We check the sign of Y, not Z! 
            // We want to rotate to drive Y to zero.
            wire y_sign = y[i][width-1]; 
            
            always @(posedge clock) begin
                if (reset) begin
                    x[i+1] <= 0; y[i+1] <= 0; z[i+1] <= 0;
                end else begin
                    // If y_sign is 0 (Positive), subtract to rotate downward.
                    x[i+1] <= y_sign ? x[i] - (y[i] >>> i) : x[i] + (y[i] >>> i);
                    y[i+1] <= y_sign ? y[i] + (x[i] >>> i) : y[i] - (x[i] >>> i);
                    z[i+1] <= y_sign ? z[i] - atan_table[i] : z[i] + atan_table[i];
                end
            end
        end
    endgenerate

    // Output the final accumulated Phase Angle!
    assign angle_out = z[16];

endmodule