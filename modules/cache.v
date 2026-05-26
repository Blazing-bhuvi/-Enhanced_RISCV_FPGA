`timescale 1ns / 1ps

module i_cache #(parameter NSETS = 64) (
    input clk, input reset, 
    input [31:0] pc_i, output [31:0] instr_o, output hit_o, output stall_o,
    output reg mem_read_o, output reg [31:0] mem_addr_o, input [31:0] mem_data_i, input mem_valid_i
);
    reg valid [0:NSETS-1];
    reg [23:0] tag [0:NSETS-1];
    reg [31:0] data [0:NSETS-1];

    // Correct word-aligned indexing
    wire [23:0] addr_tag   = pc_i[31:8];
    wire [5:0]  addr_index = pc_i[7:2];

    // Combinational Hit Detection
    wire is_hit = valid[addr_index] && (tag[addr_index] == addr_tag);
    assign hit_o = is_hit;
    
    // Data Forwarding
    assign instr_o = is_hit ? data[addr_index] : mem_data_i;

    reg fetching;
    
    // Combinational Stall
    assign stall_o = !is_hit && !(fetching && mem_valid_i);

    integer i;
    initial begin 
        mem_read_o = 0; mem_addr_o = 0; fetching = 0;
        for(i=0;i<NSETS;i=i+1) begin valid[i]=0; tag[i]=0; data[i]=0; end 
    end

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            mem_read_o <= 0; fetching <= 0;
            // FIX: Explicitly wipe the valid array on hardware reset
            for(i=0; i<NSETS; i=i+1) begin
                valid[i] <= 1'b0;
            end
        end else begin
            if (!is_hit && !fetching) begin
                mem_read_o <= 1; mem_addr_o <= pc_i; fetching <= 1;
            end else if (fetching && mem_valid_i) begin
                data[addr_index] <= mem_data_i;
                tag[addr_index] <= addr_tag;
                valid[addr_index] <= 1;
                mem_read_o <= 0; fetching <= 0;
            end
        end
    end
endmodule


module d_cache #(parameter NSETS = 64) (
    input clk, input reset, 
    input [31:0] addr_i, input [31:0] wdata_i, input rden_i, input wren_i,
    output [31:0] rdata_o, output hit_o, output stall_o,
    output reg mem_read_o, output reg mem_write_o, output reg [31:0] mem_addr_o,
    output reg [31:0] mem_wdata_o, input [31:0] mem_rdata_i, input mem_valid_i
);
    reg valid [0:NSETS-1];
    reg [23:0] tag [0:NSETS-1];
    reg [31:0] data [0:NSETS-1];

    // Correct word-aligned indexing
    wire [23:0] addr_tag   = addr_i[31:8];
    wire [5:0]  addr_index = addr_i[7:2];

    // Combinational Hit Detection
    wire is_hit = valid[addr_index] && (tag[addr_index] == addr_tag);
    assign hit_o = is_hit;
    assign rdata_o = is_hit ? data[addr_index] : mem_rdata_i;

    reg fetching, writing;
    
    // Combinational Stall
    wire read_stall = (rden_i && !is_hit) && !(fetching && mem_valid_i);
    wire write_stall = wren_i && !(writing && mem_valid_i);
    assign stall_o = read_stall | write_stall;

    integer i;
    initial begin 
        mem_read_o = 0; mem_write_o = 0; mem_addr_o = 0; mem_wdata_o = 0; fetching = 0; writing = 0;
        for(i=0;i<NSETS;i=i+1) begin valid[i]=0; tag[i]=0; data[i]=0; end 
    end

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            mem_read_o <= 0; mem_write_o <= 0; fetching <= 0; writing <= 0;
            // FIX: Explicitly wipe the valid array on hardware reset
            for(i=0; i<NSETS; i=i+1) begin
                valid[i] <= 1'b0;
            end
        end else begin
            if (rden_i && !is_hit && !fetching && !writing) begin
                mem_read_o <= 1; mem_addr_o <= addr_i; fetching <= 1;
            end else if (fetching && mem_valid_i) begin
                data[addr_index] <= mem_rdata_i; tag[addr_index] <= addr_tag; valid[addr_index] <= 1;
                mem_read_o <= 0; fetching <= 0;
            end
            
            if (wren_i && !writing && !fetching) begin
                mem_write_o <= 1; mem_addr_o <= addr_i; mem_wdata_o <= wdata_i; writing <= 1;
                data[addr_index] <= wdata_i; tag[addr_index] <= addr_tag; valid[addr_index] <= 1;
            end else if (writing && mem_valid_i) begin
                mem_write_o <= 0; writing <= 0;
            end
        end
    end
endmodule