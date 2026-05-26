`timescale 1ns / 1ps

module bootloader (
    input  wire clk,
    input  wire reset,
    
    // Switch to toggle Programming Mode vs Run Mode
    input  wire program_mode_sw, 
    
    // Connections to UART RX
    input  wire [7:0] rx_data,
    input  wire       rx_valid,
    
    // Connections to Dual-Port Instruction Memory
    output reg [31:0] mem_waddr,
    output reg [31:0] mem_wdata,
    output reg        mem_wen,
    
    // Control signal to the RISC-V CPU
    output wire       cpu_reset 
);

    // If we are in program mode, keep the CPU locked in reset
    assign cpu_reset = program_mode_sw | reset;

    reg [1:0] byte_counter;
    reg [31:0] assembled_word;

    always @(posedge clk) begin
        if (reset) begin
            mem_waddr <= 0;
            mem_wen   <= 0;
            byte_counter <= 0;
            assembled_word <= 0;
        end else if (!program_mode_sw) begin
            // When in run mode, zero out the pointers so it's ready for the next flash
            mem_waddr <= 0;
            mem_wen   <= 0;
            byte_counter <= 0;
        end else begin
            mem_wen <= 0; // Default to not writing
            
            if (rx_valid) begin
                // Pack the bytes into a 32-bit word (Little Endian format for RISC-V)
                case (byte_counter)
                    2'b00: assembled_word[7:0]   <= rx_data;
                    2'b01: assembled_word[15:8]  <= rx_data;
                    2'b10: assembled_word[23:16] <= rx_data;
                    2'b11: begin
                        assembled_word[31:24] <= rx_data;
                        mem_wdata <= {rx_data, assembled_word[23:0]}; // Push the full word
                        mem_wen   <= 1; // Trigger the write to memory
                    end
                endcase
                
                // Increment counter, and if we hit 4 bytes, increment the memory address
                if (byte_counter == 3) begin
                    byte_counter <= 0;
                    mem_waddr <= mem_waddr + 4; 
                end else begin
                    byte_counter <= byte_counter + 1;
                end
            end
            
            // Auto-increment the address to prepare for the next word after writing
            if (mem_wen) begin
                mem_wen <= 0;
            end
        end
    end
endmodule