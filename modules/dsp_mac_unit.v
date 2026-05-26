`timescale 1ns / 1ps

module mac_unit (
    input  wire        clk,
    input  wire        clean_rst,
    input  wire        clean_acc,
    input  wire [31:0] val_a,
    input  wire [31:0] val_b,
    output reg  [15:0] led_acc = 0
);
    reg [63:0] accumulator = 0;
    wire [63:0] product;

    // Explicitly cast to 64-bit BEFORE multiplying to prevent data loss
    assign product = {32'd0, val_a} * {32'd0, val_b};

    always @(posedge clk) begin
        if (clean_rst) begin
            accumulator <= 0;
            led_acc <= 0;
        end else if (clean_acc) begin
            // Accumulate instantly on pipeline signal
            accumulator <= accumulator + product;
            led_acc <= (accumulator + product);
        end
    end
endmodule