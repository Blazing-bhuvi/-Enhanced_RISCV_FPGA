`timescale 1ns / 1ps

module MEM_WB_new (
    input clk,
    input reset,
    input stall,

    // From EX/MEM
    input [31:0] ex_result_i,
    input [31:0] store_data_i,
    input [ 4:0] dest_reg_sel_i,
    input [ 2:0] alu_op_i,
    input        mem_write_i,
    input        mem_to_reg_i,
    input        reg_write_i,
    input        mac_acc_i,
    input        mac_clr_i,

    // To Data Memory
    output [31:0] dmem_write_address_o,
    output [31:0] dmem_write_data_o,
    output [ 3:0] dmem_write_byte_o,
    output        dmem_mem_write_o,
    output [31:0] dmem_read_address_o, // For reading
    input  [31:0] dmem_read_data_i,

    // To WB
    output reg [31:0] wb_mem_read_data_o,
    output reg [31:0] wb_ex_result_o,
    output reg [ 4:0] wb_dest_reg_sel_o,
    output reg        wb_mem_to_reg_o,
    output reg        wb_reg_write_o,
    output reg        wb_mac_acc_o,
    output reg        wb_mac_clr_o
);

  `include "opcode.vh"

  assign dmem_write_address_o = ex_result_i;
  assign dmem_mem_write_o     = mem_write_i;
  assign dmem_read_address_o  = ex_result_i;

  reg [31:0] write_data;
  reg [ 3:0] write_byte;

  // Store data formatting (from wb.v)
  always @(*) begin
    write_data = 32'h0;
    write_byte = 4'h0;
    if (mem_write_i) begin
      case (alu_op_i)
        SB: begin
          write_data = {4{store_data_i[7:0]}};
          case (ex_result_i[1:0])
            2'b00:   write_byte = 4'b0001;
            2'b01:   write_byte = 4'b0010;
            2'b10:   write_byte = 4'b0100;
            default: write_byte = 4'b1000;
          endcase
        end
        SH: begin
          write_data = {2{store_data_i[15:0]}};
          write_byte = ex_result_i[1] ? 4'b1100 : 4'b0011;
        end
        SW: begin
          write_data = store_data_i;
          write_byte = 4'b1111;
        end
        default: ;
      endcase
    end
  end

  assign dmem_write_data_o = write_data;
  assign dmem_write_byte_o = write_byte;

  reg [31:0] read_data_formatted;

  // Load data formatting (from wb.v)
  always @(*) begin
    case (alu_op_i)
      LB: begin
        case (ex_result_i[1:0])
          2'b00: read_data_formatted = {{24{dmem_read_data_i[7]}}, dmem_read_data_i[7:0]};
          2'b01: read_data_formatted = {{24{dmem_read_data_i[15]}}, dmem_read_data_i[15:8]};
          2'b10: read_data_formatted = {{24{dmem_read_data_i[23]}}, dmem_read_data_i[23:16]};
          2'b11: read_data_formatted = {{24{dmem_read_data_i[31]}}, dmem_read_data_i[31:24]};
        endcase
      end
      LH: begin
        read_data_formatted = ex_result_i[1] ? {{16{dmem_read_data_i[31]}}, dmem_read_data_i[31:16]} : {{16{dmem_read_data_i[15]}}, dmem_read_data_i[15:0]};
      end
      LW: read_data_formatted = dmem_read_data_i;
      LBU: begin
        case (ex_result_i[1:0])
          2'b00: read_data_formatted = {24'h0, dmem_read_data_i[7:0]};
          2'b01: read_data_formatted = {24'h0, dmem_read_data_i[15:8]};
          2'b10: read_data_formatted = {24'h0, dmem_read_data_i[23:16]};
          2'b11: read_data_formatted = {24'h0, dmem_read_data_i[31:24]};
        endcase
      end
      LHU: begin
        read_data_formatted = ex_result_i[1] ? {16'h0, dmem_read_data_i[31:16]} : {16'h0, dmem_read_data_i[15:0]};
      end
      default: read_data_formatted = dmem_read_data_i;
    endcase
  end

  // MEM/WB Pipeline Register
  always @(posedge clk or negedge reset) begin
    if (!reset) begin
      wb_mem_read_data_o <= 32'h0;
      wb_ex_result_o      <= 32'h0;
      wb_dest_reg_sel_o  <= 5'h0;
      wb_mem_to_reg_o    <= 1'b0;
      wb_reg_write_o     <= 1'b0;
      wb_mac_acc_o       <= 1'b0;
      wb_mac_clr_o       <= 1'b0;
    end else if (!stall) begin
      wb_mem_read_data_o <= read_data_formatted;
      wb_ex_result_o      <= ex_result_i;
      wb_dest_reg_sel_o  <= dest_reg_sel_i;
      wb_mem_to_reg_o    <= mem_to_reg_i;
      wb_reg_write_o     <= reg_write_i;
      wb_mac_acc_o       <= mac_acc_i;
      wb_mac_clr_o       <= mac_clr_i;
    end
  end

endmodule
