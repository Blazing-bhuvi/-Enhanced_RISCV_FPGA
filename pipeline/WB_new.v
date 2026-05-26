`timescale 1ns / 1ps

module WB_new (
    // From MEM/WB
    input [31:0] mem_read_data_i,
    input [31:0] ex_result_i,
    input [ 4:0] dest_reg_sel_i,
    input        mem_to_reg_i,
    input        reg_write_i,

    // To Register File
    output [31:0] rf_write_data_o,
    output [ 4:0] rf_write_dest_o,
    output        rf_reg_write_o
);

  assign rf_write_data_o = mem_to_reg_i ? mem_read_data_i : ex_result_i;
  assign rf_write_dest_o = dest_reg_sel_i;
  assign rf_reg_write_o  = reg_write_i;

endmodule
