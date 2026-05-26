`timescale 1ns / 1ps

module uart_tx (
    input  wire clk,
    input  wire reset,
    input  wire [7:0] data,
    input  wire start,       // Pulse high to start transmitting
    output reg  tx_out,      // Outgoing serial line
    output wire busy         // High while transmitting
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

    assign busy = (state != IDLE);

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            tx_out <= 1; // Idle state for UART is HIGH
        end else begin
            case (state)
                IDLE: begin
                    tx_out <= 1;
                    clk_count <= 0;
                    bit_index <= 0;
                    if (start) begin
                        shift_reg <= data;
                        state <= START;
                    end
                end
                
                START: begin
                    tx_out <= 0; // Send Start Bit (LOW)
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        state <= DATA;
                    end
                end
                
                DATA: begin
                    tx_out <= shift_reg[bit_index]; // Send Data Bits
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1;
                        end else begin
                            bit_index <= 0;
                            state <= STOP;
                        end
                    end
                end
                
                STOP: begin
                    tx_out <= 1; // Send Stop Bit (HIGH)
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        state <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule