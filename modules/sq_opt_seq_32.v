`timescale 1ns / 1ps
module sq_opt_seq (
    input clk, reset, start,
    input [31:0] data_in,
    output reg [63:0] data_out,
    output reg done
);
    reg [5:0] i;
    reg [63:0] sum;
    reg [31:0] data_in_reg;

    integer k, j;
    reg [63:0] temp_sum;

    always @(posedge clk) begin
        if (reset) begin
            done <= 0;
            sum <= 64'd0;
            i <= 6'd0;
            data_out <= 64'd0;
            data_in_reg <= 32'd0;
        end else begin
            if (i == 0) begin
                if (start) begin
                    data_in_reg <= data_in;
                    // Cycle 0: Calculate all diagonal terms
                    temp_sum = 64'd0;
                    for (k = 0; k < 32; k = k + 1) begin
                        if (data_in[k]) begin
                            temp_sum = temp_sum + (64'd1 << (2 * k));
                        end
                    end
                    sum <= temp_sum;
                    i <= 6'd1;
                    done <= 0;
                end else begin
                    done <= 0;
                end
            end else if (i >= 1 && i <= 16) begin
                // Cycles 1-16: Process two rows of cross-products per cycle
                temp_sum = sum;
                
                // Row 1: index = (i-1)*2
                for (j = 0; j < 32; j = j + 1) begin
                    if (j > ((i-1)*2)) begin
                        if (data_in_reg[(i-1)*2] && data_in_reg[j]) begin
                            temp_sum = temp_sum + (64'd1 << ((i-1)*2 + j + 1));
                        end
                    end
                end
                
                // Row 2: index = (i-1)*2 + 1
                for (j = 0; j < 32; j = j + 1) begin
                    if (j > ((i-1)*2 + 1)) begin
                        if (data_in_reg[(i-1)*2 + 1] && data_in_reg[j]) begin
                            temp_sum = temp_sum + (64'd1 << ((i-1)*2 + 1 + j + 1));
                        end
                    end
                end

                sum <= temp_sum;

                if (i == 16) begin
                    data_out <= temp_sum;
                    done <= 1;
                    i <= 0;
                end else begin
                    i <= i + 1;
                end
            end else begin
                i <= 0;
                done <= 0;
            end
        end
    end
endmodule
