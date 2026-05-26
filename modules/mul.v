`timescale 1ns / 1ps

module mul_shift_add (
    input wire clk,
    input wire reset,
    input wire start,         
    input wire [31:0] A,      
    input wire [31:0] B, 
    input wire is_signed_A,  // 1 = Signed, 0 = Unsigned     
    input wire is_signed_B,  // 1 = Signed, 0 = Unsigned
    output reg [63:0] product,
    output reg done
);

    reg [63:0] multiplicand_reg;
    reg [31:0] multiplier_reg;
    reg [63:0] acc;         // Accumulator for the raw addition
    reg [5:0] count;
    reg state;              // Only need 1 bit for state now (0=IDLE, 1=CALC)
    reg final_sign;

    localparam IDLE = 1'b0;
    localparam CALC = 1'b1;

    // Combinational logic to find absolute values before shifting
    wire sign_A = is_signed_A & A[31];
    wire sign_B = is_signed_B & B[31];
    wire [31:0] abs_A = sign_A ? (~A + 1'b1) : A;
    wire [31:0] abs_B = sign_B ? (~B + 1'b1) : B;

    always @(posedge clk) begin
        if (reset) begin
            product <= 64'b0;
            acc <= 64'b0;
            done <= 1'b0;
            state <= IDLE;
            count <= 6'b0;
            final_sign <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        done <= 1'b0;
                        multiplicand_reg <= {32'd0, abs_A};
                        multiplier_reg <= abs_B;
                        acc <= 64'b0;
                        count <= 6'b0;
                        final_sign <= sign_A ^ sign_B; 
                        state <= CALC;
                    end
                end
                
                CALC: begin
                    if (count < 32) begin
                        if (multiplier_reg[0] == 1'b1) begin
                            acc <= acc + multiplicand_reg;
                        end
                        multiplicand_reg <= multiplicand_reg << 1;
                        multiplier_reg <= multiplier_reg >> 1;
                        count <= count + 1;
                    end else begin
                        // On the cycle after the 32nd shift, output the result
                        product <= final_sign ? (~acc + 1'b1) : acc;
                        done <= 1'b1;
                        state <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule