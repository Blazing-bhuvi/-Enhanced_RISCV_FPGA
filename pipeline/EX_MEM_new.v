`timescale 1ns / 1ps

module EX_MEM_new (
    input clk,
    input reset,
    input stall,

    // From ID/EX
    input [31:0] pc_i,
    input [31:0] reg_rdata1_i,
    input [31:0] reg_rdata2_i,
    input [31:0] immediate_i,
    input [ 4:0] dest_reg_sel_i,
    input [ 2:0] alu_op_i,
    input        immediate_sel_i,
    input        alu_i,
    input        lui_i,
    input        jal_i,
    input        jalr_i,
    input        branch_i,
    input        mem_write_i,
    input        mem_to_reg_i,
    input        arithsubtype_i,
    input        predict_taken_i,
    
    // Custom & M-Extension Outputs
    input        mac_acc_i,
    input        mac_clr_i,
    input        sq_start_i,
    input [31:0] sq_result_i,
    input        sqrt_start_i,
    input [31:0] sqrt_result_i,
    input        cordic_start_i,
    input [31:0] cordic_result_i, // Fully defined as a 32-bit input!
    input        is_m_ext_i,
    input [63:0] mul_result_i,
    input [31:0] div_quotient_i,

    // Outputs to IF & BP
    output [31:0] next_pc_o,
    output        branch_taken_o,
    output [31:0] update_pc_o,
    output        update_en_o,
    output        actual_taken_o,

    // Outputs to MEM
    output reg [31:0] mem_ex_result_o,
    output reg [31:0] mem_store_data_o,
    output reg [ 4:0] mem_dest_reg_sel_o,
    output reg [ 2:0] mem_alu_op_o,
    output reg        mem_mem_write_o,
    output reg        mem_mem_to_reg_o,
    output reg        mem_reg_write_o,
    output reg        mem_mac_acc_o,
    output reg        mem_mac_clr_o,

    output [31:0] ex_result_comb_o
    );

  `include "opcode.vh"

  wire [31:0] alu_operand1 = reg_rdata1_i;
  wire [31:0] alu_operand2 = immediate_sel_i ? immediate_i : reg_rdata2_i;
  wire [32:0] ex_result_subs = {alu_operand1[31], alu_operand1} - {alu_operand2[31], alu_operand2};
  wire [32:0] ex_result_subu = {1'b0, alu_operand1} - {1'b0, alu_operand2};
  
  reg [31:0] ex_result;
  reg [31:0] target_pc;
  reg        actual_taken;
  reg        misprediction;

  // ALU Result Logic
  always @(*) begin
    ex_result = 32'h0;
    
    if (sq_start_i) begin
        ex_result = sq_result_i; 
    end else if (sqrt_start_i) begin
        ex_result = sqrt_result_i;
    end else if (cordic_start_i) begin
        ex_result = cordic_result_i; // Routes the 32-bit angle straight to the register file
    end else if (is_m_ext_i) begin
        case (alu_op_i)
            MUL:                  ex_result = mul_result_i[31:0];
            MULH, MULHSU, MULHU:  ex_result = mul_result_i[63:32];
            DIV, DIVU, REM, REMU: ex_result = div_quotient_i; 
            default:              ex_result = 32'h0;
        endcase
    end else begin
        case (1'b1)
          mem_write_i, mem_to_reg_i: ex_result = alu_operand1 + immediate_i;
          jal_i, jalr_i: ex_result = pc_i + 4;
          lui_i: ex_result = immediate_i;
          alu_i: begin
            case (alu_op_i)
              ADD:  ex_result = arithsubtype_i ? alu_operand1 - alu_operand2 : alu_operand1 + alu_operand2;
              SLL:  ex_result = alu_operand1 << alu_operand2[4:0];
              SLT:  ex_result = {31'b0, ex_result_subs[32]};
              SLTU: ex_result = {31'b0, ex_result_subu[32]};
              XOR:  ex_result = alu_operand1 ^ alu_operand2;
              SR:   ex_result = arithsubtype_i ? $signed(alu_operand1) >>> alu_operand2[4:0] : alu_operand1 >> alu_operand2[4:0];
              OR:   ex_result = alu_operand1 | alu_operand2;
              AND:  ex_result = alu_operand1 & alu_operand2;
              default: ex_result = 32'h0;
            endcase
          end
          default: ex_result = 32'h0;
        endcase
    end
  end

  // Next PC / Branch Logic
  always @(*) begin
    target_pc    = pc_i + 4;
    actual_taken = 1'b0;
    misprediction = 1'b0;

    if (jal_i) begin
        actual_taken = 1'b1;
    end else if (jalr_i) begin
        target_pc    = alu_operand1 + immediate_i;
        actual_taken = 1'b1;
        misprediction = 1'b1; // JALR always flushes
    end else if (branch_i) begin
      case (alu_op_i)
        BEQ:  actual_taken = (ex_result_subs[31:0] == 0);
        BNE:  actual_taken = (ex_result_subs[31:0] != 0);
        BLT:  actual_taken = ex_result_subs[32];
        BGE:  actual_taken = !ex_result_subs[32];
        BLTU: actual_taken = ex_result_subu[32];
        BGEU: actual_taken = !ex_result_subu[32];
        default: actual_taken = 1'b0;
      endcase
      
      misprediction = (actual_taken != predict_taken_i);
      if (actual_taken) target_pc = pc_i + immediate_i;
      else target_pc = pc_i + 4;
    end
  end

  assign next_pc_o      = target_pc;
  assign branch_taken_o = misprediction || jalr_i;
  assign update_pc_o    = pc_i;
  assign update_en_o    = branch_i;
  assign actual_taken_o = actual_taken;
  assign ex_result_comb_o = ex_result;

  // EX/MEM Pipeline Register
  always @(posedge clk or negedge reset) begin
    if (!reset) begin
      mem_ex_result_o    <= 32'h0;
      mem_store_data_o   <= 32'h0;
      mem_dest_reg_sel_o <= 5'h0;
      mem_alu_op_o       <= 3'h0;
      mem_mem_write_o    <= 1'b0;
      mem_mem_to_reg_o   <= 1'b0;
      mem_reg_write_o    <= 1'b0;
      mem_mac_acc_o      <= 1'b0;
      mem_mac_clr_o      <= 1'b0;
    end else if (!stall) begin
      mem_ex_result_o    <= ex_result;
      mem_store_data_o   <= reg_rdata2_i; // Original data for store
      mem_dest_reg_sel_o <= dest_reg_sel_i;
      mem_alu_op_o       <= alu_op_i;
      mem_mem_write_o    <= mem_write_i;
      mem_mem_to_reg_o   <= mem_to_reg_i;
      mem_reg_write_o    <= (alu_i | lui_i | jal_i | jalr_i | mem_to_reg_i | sq_start_i | is_m_ext_i | sqrt_start_i | cordic_start_i);
      mem_mac_acc_o      <= mac_acc_i;
      mem_mac_clr_o      <= mac_clr_i;
    end
  end

endmodule