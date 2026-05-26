`timescale 1ns / 1ps

module ID_EX_new (
    input clk,
    input reset,
    input stall,
    input flush,

    // From IF/ID
    input [31:0] pc_i,
    input [31:0] instruction_i,
    input        predict_taken_i,

    // From Register File (External)
    input [31:0] reg_rdata1_i,
    input [31:0] reg_rdata2_i,

    // Outputs to EX
    output reg [31:0] ex_pc_o,
    output reg [31:0] ex_reg_rdata1_o,
    output reg [31:0] ex_reg_rdata2_o,
    output reg [31:0] ex_immediate_o,
    output reg [ 4:0] ex_dest_reg_sel_o,
    output reg [ 2:0] ex_alu_op_o,
    output reg        ex_immediate_sel_o,
    output reg        ex_alu_o,
    output reg        ex_lui_o,
    output reg        ex_jal_o,
    output reg        ex_jalr_o,
    output reg        ex_branch_o,
    output reg        ex_mem_write_o,
    output reg        ex_mem_to_reg_o,
    output reg        ex_arithsubtype_o,
    output reg        ex_illegal_inst_o,
    output reg        ex_predict_taken_o,
    
    // Custom & M-Extension Flags
    output reg        ex_mac_acc_o,
    output reg        ex_mac_clr_o,
    output reg        ex_sq_start_o,
    output reg        ex_sqrt_start_o,
    output reg        ex_cordic_start_o,
    output reg        ex_is_m_ext_o,

    // Outputs for RegFile read (ID stage)
    output [4:0] src1_select_o,
    output [4:0] src2_select_o,

    // Registered source registers for EX stage forwarding
    output reg [4:0] ex_rs1_o,
    output reg [4:0] ex_rs2_o
);
  `include "opcode.vh"

  reg [31:0] immediate;
  reg        illegal_inst;
  reg        mac_acc, mac_clr, sq_start, sqrt_start, cordic_start, is_m_ext;

  assign src1_select_o = instruction_i[`RS1];
  assign src2_select_o = instruction_i[`RS2];

  // Immediate Generation
  always @(*) begin
    immediate    = 32'h0;
    illegal_inst = 1'b0;
    mac_acc      = 1'b0;
    mac_clr      = 1'b0;
    sq_start     = 1'b0;
    sqrt_start   = 1'b0;
    cordic_start = 1'b0;
    is_m_ext     = 1'b0;
    
    case (instruction_i[`OPCODE])
      JALR: immediate = {{20{instruction_i[31]}}, instruction_i[31:20]};
      BRANCH: immediate = {{20{instruction_i[31]}}, instruction_i[7], instruction_i[30:25], instruction_i[11:8], 1'b0};
      LOAD: immediate = {{20{instruction_i[31]}}, instruction_i[31:20]};
      STORE: immediate = {{20{instruction_i[31]}}, instruction_i[31:25], instruction_i[11:7]};
      ARITHI:
      immediate = (instruction_i[`FUNC3] == SLL || instruction_i[`FUNC3] == SR)
                 ? {27'b0, instruction_i[24:20]}
                 : {{20{instruction_i[31]}}, instruction_i[31:20]};
      ARITHR: begin 
        immediate = 32'h0;
        if (instruction_i[`FUNC7] == FUNC7_M) is_m_ext = 1'b1;
      end
      LUI: immediate = {instruction_i[31:12], 12'b0};
      JAL: immediate = {{12{instruction_i[31]}}, instruction_i[19:12], instruction_i[20], instruction_i[30:21], 1'b0};
      CUSTOM: begin
        immediate = 32'h0;
        if      (instruction_i[`FUNC3] == MAC_ACC)   mac_acc = 1'b1;
        else if (instruction_i[`FUNC3] == MAC_CLR)   mac_clr = 1'b1;
        else if (instruction_i[`FUNC3] == SQ_OP)     sq_start = 1'b1;
        else if (instruction_i[`FUNC3] == SQRT_OP)   sqrt_start = 1'b1;
        else if (instruction_i[`FUNC3] == CORDIC_OP) cordic_start = 1'b1;
        else illegal_inst = 1'b1;
      end
      default: illegal_inst = 1'b1;
    endcase
  end

  // ID/EX Pipeline Register
  always @(posedge clk or negedge reset) begin
    if (!reset || flush) begin
      ex_pc_o            <= 32'h0;
      ex_reg_rdata1_o    <= 32'h0;
      ex_reg_rdata2_o    <= 32'h0;
      ex_immediate_o     <= 32'h0;
      ex_dest_reg_sel_o  <= 5'h0;
      ex_alu_op_o        <= 3'h0;
      ex_immediate_sel_o <= 1'b0;
      ex_alu_o           <= 1'b0;
      ex_lui_o           <= 1'b0;
      ex_jal_o           <= 1'b0;
      ex_jalr_o          <= 1'b0;
      ex_branch_o        <= 1'b0;
      ex_mem_write_o     <= 1'b0;
      ex_mem_to_reg_o    <= 1'b0;
      ex_arithsubtype_o  <= 1'b0;
      ex_illegal_inst_o  <= 1'b0;
      ex_rs1_o           <= 5'h0;
      ex_rs2_o           <= 5'h0;
      ex_predict_taken_o <= 1'b0;
      ex_mac_acc_o       <= 1'b0;
      ex_mac_clr_o       <= 1'b0;
      ex_sq_start_o      <= 1'b0;
      ex_sqrt_start_o    <= 1'b0;
      ex_cordic_start_o  <= 1'b0;
      ex_is_m_ext_o      <= 1'b0;
    end else if (!stall) begin
      ex_pc_o            <= pc_i;
      ex_reg_rdata1_o    <= reg_rdata1_i;
      ex_reg_rdata2_o    <= reg_rdata2_i;
      ex_immediate_o     <= immediate;
      ex_dest_reg_sel_o  <= instruction_i[`RD];
      ex_alu_op_o        <= instruction_i[`FUNC3];
      ex_immediate_sel_o <= (instruction_i[`OPCODE] == JALR) || (instruction_i[`OPCODE] == LOAD) || (instruction_i[`OPCODE] == ARITHI);
      ex_alu_o           <= (instruction_i[`OPCODE] == ARITHI) || (instruction_i[`OPCODE] == ARITHR);
      ex_lui_o           <= instruction_i[`OPCODE] == LUI;
      ex_jal_o           <= instruction_i[`OPCODE] == JAL;
      ex_jalr_o          <= instruction_i[`OPCODE] == JALR;
      ex_branch_o        <= instruction_i[`OPCODE] == BRANCH;
      ex_mem_write_o     <= instruction_i[`OPCODE] == STORE;
      ex_mem_to_reg_o    <= instruction_i[`OPCODE] == LOAD;
      ex_arithsubtype_o  <= instruction_i[`SUBTYPE] && !(instruction_i[`OPCODE] == ARITHI && instruction_i[`FUNC3] == ADD);
      ex_illegal_inst_o  <= illegal_inst;
      ex_rs1_o           <= instruction_i[`RS1];
      ex_rs2_o           <= instruction_i[`RS2];
      ex_predict_taken_o <= predict_taken_i;
      ex_mac_acc_o       <= mac_acc;
      ex_mac_clr_o       <= mac_clr;
      ex_sq_start_o      <= sq_start;
      ex_sqrt_start_o    <= sqrt_start;
      ex_cordic_start_o  <= cordic_start;
      ex_is_m_ext_o      <= is_m_ext;
    end
  end

endmodule