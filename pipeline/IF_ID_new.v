`timescale 1ns / 1ps

module IF_ID_new #(
    parameter [31:0] RESET = 32'h0000_0000
) (
    input clk,
    input reset,
    input stall,

    // Branch/Jump from EX
    input [31:0] next_pc_i,
    input        branch_taken_i,
    
    // Branch Prediction from IF
    input        predict_taken_i,

    // Instruction Memory interface
    output [31:0] inst_mem_address_o,
    input  [31:0] inst_mem_read_data_i,

    // Outputs to ID
    output reg [31:0] id_pc_o,
    output reg [31:0] id_instruction_o,
    output reg        id_predict_taken_o
);

  `include "opcode.vh"
  reg [31:0] pc;

  // Partial decode for prediction
  wire [31:0] inst = inst_mem_read_data_i;
  wire is_branch = (inst[`OPCODE] == BRANCH);
  wire is_jal = (inst[`OPCODE] == JAL);
  
  wire [31:0] b_imm = {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};
  wire [31:0] j_imm = {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};
  wire [31:0] target_offset = is_jal ? j_imm : b_imm;

  // Next PC logic
  wire [31:0] pc_plus_4 = pc + 4;
  wire [31:0] pc_plus_target = pc + target_offset;
  
  wire use_prediction = (is_branch && predict_taken_i) || is_jal;
  
  wire [31:0] next_pc_w = (!reset) ? RESET : 
                          (branch_taken_i ? next_pc_i : 
                          (use_prediction ? pc_plus_target : pc_plus_4));

  // Output the NEXT PC to memory so it can be sampled at the next edge
  assign inst_mem_address_o = pc;

  // PC update
  always @(posedge clk or negedge reset) begin
    if (!reset) begin
      pc <= RESET;
    end else if (!stall) begin
      pc <= next_pc_w;
    end
  end

  // IF/ID Pipeline Register
  always @(posedge clk or negedge reset) begin
    if (!reset) begin
      id_pc_o          <= 32'h0;
      id_instruction_o <= 32'h0000_0013; // NOP (addi x0, x0, 0)
      id_predict_taken_o <= 1'b0;
    end else begin
      if (branch_taken_i) begin
        // Flush instruction if branch misprediction/jump is taken from EX
        id_pc_o          <= 32'h0;
        id_instruction_o <= 32'h0000_0013; // NOP
        id_predict_taken_o <= 1'b0;
      end else if (!stall) begin
        id_pc_o          <= pc;
        id_instruction_o <= inst_mem_read_data_i;
        id_predict_taken_o <= use_prediction;
      end
    end
  end

endmodule
