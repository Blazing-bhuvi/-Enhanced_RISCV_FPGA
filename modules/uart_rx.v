`timescale 1ns / 1ps

module uart_rx (
    input  wire clk,         // 100 MHz clock
    input  wire reset,       // Active-high reset
    input  wire rx_in,       // Incoming serial line
    output reg  [7:0] data,  // The assembled byte
    output reg  valid        // Pulses high for 1 cycle when byte is ready
);

    parameter CLKS_PER_BIT = 868; // 100 MHz / 115200 baud

    localparam IDLE  = 2'b00;
    localparam START = 2'b01;
    localparam DATA  = 2'b10;
    localparam STOP  = 2'b11;

    reg [1:0] state = IDLE;
    reg [9:0] clk_count = 0;
    reg [2:0] bit_index = 0;
    reg [7:0] shift_reg = 0;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            valid <= 0;
            data  <= 0;
        end else begin
            valid <= 0; // Default to 0
            
            case (state)
                IDLE: begin
                    clk_count <= 0;
                    bit_index <= 0;
                    if (rx_in == 0) state <= START; // Start bit detected!
                end
                
                START: begin
                    if (clk_count == (CLKS_PER_BIT / 2)) begin
                        if (rx_in == 0) begin // Confirm it's a real start bit
                            clk_count <= 0;
                            state <= DATA;
                        end else state <= IDLE;
                    end else clk_count <= clk_count + 1;
                end
                
                DATA: begin
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        shift_reg[bit_index] <= rx_in; // Sample the bit
                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1;
                        end else begin
                            bit_index <= 0;
                            state <= STOP;
                        end
                    end
                end
                
                STOP: begin
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        data <= shift_reg;
                        valid <= 1; // Signal that the byte is ready!
                        state <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule