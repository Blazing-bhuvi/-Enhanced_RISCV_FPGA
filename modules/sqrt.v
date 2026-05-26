`timescale 1ns / 1ps

module sqrt_unit #(
    parameter WIDTH = 32
)(
    input clk,
    input reset,

    input start,
    input [WIDTH-1:0] rad,

    output reg busy,
    output reg valid,
    output reg [WIDTH-1:0] root
);

    reg [WIDTH-1:0] x, q;
    reg [WIDTH+1:0] ac;
    reg [WIDTH+1:0] test_res;

    reg [5:0] i;
    localparam ITER = WIDTH >> 1;

    always @(posedge clk) begin
        if (reset) begin
            busy <= 0;
            valid <= 0;
            i <= 0;
        end

        else if (start) begin
            busy <= 1;
            valid <= 0;
            i <= 0;
            q <= 0;
            {ac, x} <= {{WIDTH{1'b0}}, rad, 2'b0};
        end

        else if (busy) begin
            test_res = ac - {q, 2'b01};

            if (!test_res[WIDTH+1]) begin
                ac <= {test_res[WIDTH-1:0], x[WIDTH-1:WIDTH-2]};
                q  <= {q[WIDTH-2:0], 1'b1};
                
                // FIX: Write the newly updated value, not the old 'q'
                if (i == ITER-1) root <= {q[WIDTH-2:0], 1'b1}; 
            end else begin
                ac <= {ac[WIDTH-1:0], x[WIDTH-1:WIDTH-2]};
                q  <= q << 1;
                
                // FIX: Write the newly updated value, not the old 'q'
                if (i == ITER-1) root <= q << 1; 
            end

            x <= x << 2;

            if (i == ITER-1) begin
                busy <= 0;
                valid <= 1;
            end else begin
                i <= i + 1;
            end
        end

        else begin
            valid <= 0;
        end
    end
endmodule