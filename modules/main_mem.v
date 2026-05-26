`timescale 1ns / 1ps

module main_memory #(
    parameter MEM_SIZE = 1024,
    parameter INIT_FILE = "" 
)(
    input clk,
    input reset,
    input mem_read_i,
    input mem_write_i,
    input [31:0] addr_i,
    input [31:0] wdata_i,
    output reg [31:0] rdata_o,
    output reg valid_o
);
    reg [31:0] memory [0:MEM_SIZE-1];

    integer i;
    initial begin
        rdata_o = 0;  // Fixes the red 'X' issue in simulation
        valid_o = 0;
        for(i=0;i<MEM_SIZE;i=i+1) memory[i]=0;
            
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, memory);
        end
    end

    always @(posedge clk) begin
        valid_o <= 0;
        if (mem_read_i) begin
            rdata_o <= memory[addr_i[11:2]];
            valid_o <= 1;
        end
        if (mem_write_i) begin
            memory[addr_i[11:2]] <= wdata_i;
            valid_o <= 1;
        end
    end
endmodule