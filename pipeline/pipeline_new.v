`timescale 1ns / 1ps

module pipe_new #(
    parameter [31:0] RESET = 32'h0000_0000
) (
    input         clk,
    input         reset,
    input         stall,
    output        exception,
    output [31:0] pc_out,

    // IMEM Interface
    output [31:0] inst_mem_address,
    input         inst_mem_is_valid,
    input  [31:0] inst_mem_read_data,
    output        inst_mem_is_ready,

    // DMEM Interface
    output [31:0] dmem_read_address,
    output        dmem_read_ready,
    input  [31:0] dmem_read_data_temp,
    input         dmem_read_valid,
    output [31:0] dmem_write_address,
    output        dmem_write_ready,
    output [31:0] dmem_write_data,
    output [ 3:0] dmem_write_byte,
    input         dmem_write_valid,
    
    output [31:0] latest_result,
    output reg [15:0] led_out // <--- ADD THIS BRAND NEW PORT!
);
  // -- Internal Wires -- //
  wire [31:0] id_pc, id_instruction;
  wire        id_predict_taken;
  wire [31:0] ex_pc, ex_reg_rdata1, ex_reg_rdata2, ex_immediate;
  wire [ 4:0] ex_dest_reg_sel, id_src1_sel, id_src2_sel, ex_src1_sel, ex_src2_sel;
  wire [ 2:0] ex_alu_op;
  wire        ex_immediate_sel, ex_alu, ex_lui, ex_jal, ex_jalr, ex_branch, ex_mem_write, ex_mem_to_reg;
  wire        ex_arithsubtype, ex_illegal_inst, ex_predict_taken, ex_mac_acc, ex_mac_clr;
  wire        ex_sq_start, ex_sqrt_start, ex_cordic_start, ex_is_m_ext;
  wire [31:0] next_pc, mem_ex_result, ex_result_comb, mem_store_data, update_pc;
  wire [ 4:0] mem_dest_reg_sel;
  wire [ 2:0] mem_alu_op;
  wire        branch_taken, mem_mem_write, mem_mem_to_reg, mem_reg_write, mem_mac_acc, mem_mac_clr, update_en, actual_taken;
  wire [31:0] wb_mem_read_data, wb_ex_result, rf_write_data;
  wire [ 4:0] wb_dest_reg_sel, rf_write_dest;
  wire        wb_mem_to_reg, wb_reg_write, wb_mac_acc, wb_mac_clr, rf_reg_write;

  // Register File
  reg [31:0] regs [31:1];
  wire [31:0] reg_rdata1, reg_rdata2;

  // ---------------------------------------------------------------------------
  // HAZARD DETECTION UNIT & FORWARDING MUX
  // ---------------------------------------------------------------------------
  wire [1:0] forward_a, forward_b;
  wire hz_stall_if, hz_stall_id, hz_flush_id, hz_flush_ex;
  reg [31:0] forwarded_rdata1, forwarded_rdata2;

  wire ex_reg_write = (ex_alu | ex_lui | ex_jal | ex_jalr | ex_mem_to_reg | ex_sq_start | ex_is_m_ext | ex_sqrt_start | ex_cordic_start);

  hazard_unit_new hazard_unit (
      .id_opcode(id_instruction[6:0]),
      .id_rs1(id_src1_sel),
      .id_rs2(id_src2_sel),
      .ex_rs1(ex_src1_sel),
      .ex_rs2(ex_src2_sel),
      .ex_rd(ex_dest_reg_sel),
      .mem_rd(mem_dest_reg_sel),
      .wb_rd(rf_write_dest),
      .ex_reg_write(ex_reg_write),
      .mem_reg_write(mem_reg_write),
      .wb_reg_write(rf_reg_write),
      .ex_mem_to_reg(ex_mem_to_reg),
      .mem_mem_to_reg(mem_mem_to_reg),
      .branch_taken(branch_taken),
      .ex_busy(math_stall), 
      .forward_a(forward_a),
      .forward_b(forward_b),
      .stall_if(hz_stall_if),
      .stall_id(hz_stall_id),
      .flush_id(hz_flush_id),
      .flush_ex(hz_flush_ex)
  );

  always @(*) begin
      case (forward_a)
          2'b01:   forwarded_rdata1 = mem_mem_to_reg ? dmem_read_data_temp : mem_ex_result; 
          2'b10:   forwarded_rdata1 = rf_write_data;
          default: forwarded_rdata1 = ex_reg_rdata1;
      endcase

      case (forward_b)
          2'b01:   forwarded_rdata2 = mem_mem_to_reg ? dmem_read_data_temp : mem_ex_result;
          2'b10:   forwarded_rdata2 = rf_write_data;
          default: forwarded_rdata2 = ex_reg_rdata2;
      endcase
  end

  // ---------------------------------------------------------------------------
  // Complex Stall & Accelerator Logic
  // ---------------------------------------------------------------------------
  wire [63:0] sq_data_out; wire sq_done; reg sq_active;
  always @(posedge clk or negedge reset) begin
      if (!reset) sq_active <= 0;
      else if (ex_sq_start && !sq_active && !sq_done) sq_active <= 1;
      else if (sq_done) sq_active <= 0;
  end
  wire actual_sq_start = ex_sq_start && !sq_active;
  wire sq_stall = ex_sq_start && !sq_done;

  wire [31:0] sqrt_root; wire sqrt_valid; wire sqrt_busy; reg sqrt_active;
  always @(posedge clk or negedge reset) begin
      if (!reset) sqrt_active <= 0;
      else if (ex_sqrt_start && !sqrt_active && !sqrt_valid) sqrt_active <= 1;
      else if (sqrt_valid) sqrt_active <= 0;
  end
  wire actual_sqrt_start = ex_sqrt_start && !sqrt_active;
  wire sqrt_stall = ex_sqrt_start && !sqrt_valid;

  // --- UPDATED CORDIC WIRES ---
  wire [31:0] cordic_angle_out;
  reg  [16:0] cordic_shift; reg cordic_active;
  
  always @(posedge clk or negedge reset) begin
      if (!reset) cordic_active <= 0;
      else if (ex_cordic_start && !cordic_active && !cordic_shift[16]) cordic_active <= 1;
      else if (cordic_shift[16]) cordic_active <= 0;
  end
  wire actual_cordic_start = ex_cordic_start && !cordic_active;
  
  always @(posedge clk or negedge reset) begin
      if (!reset) cordic_shift <= 17'b0;
      else cordic_shift <= {cordic_shift[15:0], actual_cordic_start};
  end
  wire cordic_stall = ex_cordic_start && !cordic_shift[16];

  wire [63:0] mul_product; wire mul_done; reg mul_done_d; 
  always @(posedge clk or negedge reset) begin
      if (!reset) mul_done_d <= 0;
      else mul_done_d <= mul_done;
  end
  wire mul_done_pulse = mul_done && !mul_done_d;

  wire [31:0] div_quotient; wire [31:0] div_remainder; wire div_done;
  reg m_active;
  always @(posedge clk or negedge reset) begin
      if (!reset) m_active <= 0;
      else if (ex_is_m_ext && !m_active && !(mul_done_pulse || div_done)) m_active <= 1;
      else if (mul_done_pulse || div_done) m_active <= 0;
  end
  wire actual_mul_start = ex_is_m_ext && (ex_alu_op[2] == 1'b0) && !m_active;
  wire actual_div_start = ex_is_m_ext && (ex_alu_op[2] == 1'b1) && !m_active;
  wire m_stall = ex_is_m_ext && !(mul_done_pulse || div_done);

  // COMBINED STALL LOGIC WITH HAZARD UNIT
  assign math_stall = sq_stall || m_stall || sqrt_stall || cordic_stall;
  wire final_stall_if = stall || hz_stall_if;
  wire final_stall_id = stall || hz_stall_id;
  wire final_stall_ex = stall || math_stall;

  // *** THE FIX: SAFE FLUSH LOGIC ***
  // Prevent the Hazard Unit from flushing the pipeline while a cache or math stall is freezing it!
  wire safe_flush_id = hz_flush_id && !stall;
  wire safe_flush_ex = hz_flush_ex && !stall && !math_stall;

  // ---------------------------------------------------------------------------
  // Sub-Module Instantiations
  // ---------------------------------------------------------------------------
  branch_predictor bp (.clk(clk), .rst(~reset), .fetch_pc(inst_mem_address), .predict_taken(bp_predict_taken), .update_pc(update_pc), .update_en(update_en), .actual_taken(actual_taken));

  reg mac_active;
  always @(posedge clk or negedge reset) begin
      if (!reset) mac_active <= 0;
      else if (ex_mac_acc && !mac_active) mac_active <= 1;
      else if (!ex_mac_acc) mac_active <= 0;
  end
  wire actual_mac_acc = ex_mac_acc && !mac_active;
  wire [15:0] mac_led;
  mac_unit mac (.clk(clk), .clean_rst(~reset || ex_mac_clr), .clean_acc(actual_mac_acc), .val_a(forwarded_rdata1), .val_b(forwarded_rdata2), .led_acc(mac_led));

  sq_opt_seq sq (.clk(clk), .reset(~reset), .start(actual_sq_start), .data_in(forwarded_rdata1), .data_out(sq_data_out), .done(sq_done));
  sqrt_unit sqrt_u (.clk(clk), .reset(~reset), .start(actual_sqrt_start), .rad(forwarded_rdata1), .busy(sqrt_busy), .valid(sqrt_valid), .root(sqrt_root));
  
  // --- UPDATED CORDIC INSTANTIATION ---
  cordic cordic_u (
      .clock(clk), 
      .reset(~reset), 
      .x_start(forwarded_rdata2[15:0]), // rs2 holds sum_x
      .y_start(forwarded_rdata1[15:0]), // rs1 holds sum_y
      .angle_out(cordic_angle_out)      // The new Phase Angle output
  );

  mul_shift_add mul_u (.clk(clk), .reset(~reset), .start(actual_mul_start), .A(forwarded_rdata1), .B(forwarded_rdata2), .is_signed_A(ex_alu_op == 3'b000 || ex_alu_op == 3'b001 || ex_alu_op == 3'b010), .is_signed_B(ex_alu_op == 3'b000 || ex_alu_op == 3'b001), .product(mul_product), .done(mul_done));
  div_unit div_u (.clk(clk), .reset(~reset), .start(actual_div_start), .div(ex_alu_op == 3'b100), .divu(ex_alu_op == 3'b101), .rem(ex_alu_op == 3'b110), .remu(ex_alu_op == 3'b111), .fdiv(1'b0), .a(forwarded_rdata1), .b(forwarded_rdata2), .busy(), .done(div_done), .valid(), .dbz(), .ovf(), .stall(), .val(div_quotient), .remainder(div_remainder));

  // ---------------------------------------------------------------------------
  // Register File Logic
  // ---------------------------------------------------------------------------
  assign reg_rdata1 = (id_src1_sel == 5'd0) ? 32'b0 : (rf_reg_write && (rf_write_dest != 5'd0) && (rf_write_dest == id_src1_sel)) ? rf_write_data : regs[id_src1_sel];
  assign reg_rdata2 = (id_src2_sel == 5'd0) ? 32'b0 : (rf_reg_write && (rf_write_dest != 5'd0) && (rf_write_dest == id_src2_sel)) ? rf_write_data : regs[id_src2_sel];

  integer i;
  always @(posedge clk or negedge reset) begin
    if (!reset) begin
      for (i = 1; i < 32; i = i + 1) regs[i] <= 32'b0;
    end else if (rf_reg_write && rf_write_dest != 5'd0) begin
      regs[rf_write_dest] <= rf_write_data;
    end
  end

  // ---------------------------------------------------------------------------
  // Pipeline Stage Instantiations
  // ---------------------------------------------------------------------------
  
  IF_ID_new #(.RESET(RESET)) if_stage (.clk(clk), .reset(reset), .stall(final_stall_if), .next_pc_i(next_pc), .branch_taken_i(safe_flush_id), .predict_taken_i(bp_predict_taken), .inst_mem_address_o(inst_mem_address), .inst_mem_read_data_i(inst_mem_read_data), .id_pc_o(id_pc), .id_instruction_o(id_instruction), .id_predict_taken_o(id_predict_taken));

  assign inst_mem_is_ready = !final_stall_if; assign pc_out = id_pc; 

  ID_EX_new id_stage (.clk(clk), .reset(reset), .stall(final_stall_id), .flush(safe_flush_ex), .pc_i(id_pc), .instruction_i(id_instruction), .predict_taken_i(id_predict_taken), .reg_rdata1_i(reg_rdata1), .reg_rdata2_i(reg_rdata2), .ex_pc_o(ex_pc), .ex_reg_rdata1_o(ex_reg_rdata1), .ex_reg_rdata2_o(ex_reg_rdata2), .ex_immediate_o(ex_immediate), .ex_dest_reg_sel_o(ex_dest_reg_sel), .ex_alu_op_o(ex_alu_op), .ex_immediate_sel_o(ex_immediate_sel), .ex_alu_o(ex_alu), .ex_lui_o(ex_lui), .ex_jal_o(ex_jal), .ex_jalr_o(ex_jalr), .ex_branch_o(ex_branch), .ex_mem_write_o(ex_mem_write), .ex_mem_to_reg_o(ex_mem_to_reg), .ex_arithsubtype_o(ex_arithsubtype), .ex_illegal_inst_o(ex_illegal_inst), .ex_predict_taken_o(ex_predict_taken), .ex_mac_acc_o(ex_mac_acc), .ex_mac_clr_o(ex_mac_clr), .ex_sq_start_o(ex_sq_start), .ex_sqrt_start_o(ex_sqrt_start), .ex_cordic_start_o(ex_cordic_start), .ex_is_m_ext_o(ex_is_m_ext), .src1_select_o(id_src1_sel), .src2_select_o(id_src2_sel), .ex_rs1_o(ex_src1_sel), .ex_rs2_o(ex_src2_sel));

  assign exception = ex_illegal_inst;

  EX_MEM_new ex_stage (
      .clk(clk), .reset(reset), .stall(final_stall_ex), 
      .pc_i(ex_pc), 
      .reg_rdata1_i(forwarded_rdata1), .reg_rdata2_i(forwarded_rdata2), 
      .immediate_i(ex_immediate), 
      .dest_reg_sel_i(ex_dest_reg_sel), .alu_op_i(ex_alu_op), 
      .immediate_sel_i(ex_immediate_sel), .alu_i(ex_alu), .lui_i(ex_lui), .jal_i(ex_jal), .jalr_i(ex_jalr), .branch_i(ex_branch), 
      .mem_write_i(ex_mem_write), .mem_to_reg_i(ex_mem_to_reg), .arithsubtype_i(ex_arithsubtype), .predict_taken_i(ex_predict_taken), 
      .mac_acc_i(ex_mac_acc), .mac_clr_i(ex_mac_clr), 
      .sq_start_i(ex_sq_start), .sq_result_i(sq_data_out[31:0]), 
      .sqrt_start_i(ex_sqrt_start), .sqrt_result_i(sqrt_root), 
      .cordic_start_i(ex_cordic_start), 
      .cordic_result_i(cordic_angle_out), // Route the new 32-bit angle here!
      .is_m_ext_i(ex_is_m_ext), .mul_result_i(mul_product), .div_quotient_i(div_quotient), 
      .next_pc_o(next_pc), .branch_taken_o(branch_taken), .update_pc_o(update_pc), .update_en_o(update_en), .actual_taken_o(actual_taken), 
      .mem_ex_result_o(mem_ex_result), .mem_store_data_o(mem_store_data), .mem_dest_reg_sel_o(mem_dest_reg_sel), 
      .mem_alu_op_o(mem_alu_op), .mem_mem_write_o(mem_mem_write), .mem_mem_to_reg_o(mem_mem_to_reg), 
      .mem_reg_write_o(mem_reg_write), .mem_mac_acc_o(mem_mac_acc), .mem_mac_clr_o(mem_mac_clr), 
      .ex_result_comb_o(ex_result_comb)
  );

  MEM_WB_new mem_stage (.clk(clk), .reset(reset), .stall(stall), .ex_result_i(mem_ex_result), .store_data_i(mem_store_data), .dest_reg_sel_i(mem_dest_reg_sel), .alu_op_i(mem_alu_op), .mem_write_i(mem_mem_write && !math_stall), .mem_to_reg_i(mem_mem_to_reg), .reg_write_i(mem_reg_write && !math_stall), .mac_acc_i(mem_mac_acc && !math_stall), .mac_clr_i(mem_mac_clr && !math_stall), .dmem_write_address_o(dmem_write_address), .dmem_write_data_o(dmem_write_data), .dmem_write_byte_o(dmem_write_byte), .dmem_mem_write_o(dmem_write_ready), .dmem_read_address_o(), .dmem_read_data_i(dmem_read_data_temp), .wb_mem_read_data_o(wb_mem_read_data), .wb_ex_result_o(wb_ex_result), .wb_dest_reg_sel_o(wb_dest_reg_sel), .wb_mem_to_reg_o(wb_mem_to_reg), .wb_reg_write_o(wb_reg_write), .wb_mac_acc_o(wb_mac_acc), .wb_mac_clr_o(wb_mac_clr));

  assign dmem_read_address = mem_ex_result;
  assign dmem_read_ready = mem_mem_to_reg && !math_stall;

  WB_new wb_stage (.mem_read_data_i(wb_mem_read_data), .ex_result_i(wb_ex_result), .dest_reg_sel_i(wb_dest_reg_sel), .mem_to_reg_i(wb_mem_to_reg), .reg_write_i(wb_reg_write), .rf_write_data_o(rf_write_data), .rf_write_dest_o(rf_write_dest), .rf_reg_write_o(rf_reg_write));

  // -------- RESULT OUTPUT BUFFER -------- //
  reg [31:0] display_buffer;
  always @(posedge clk) begin
      if (!reset) begin
          display_buffer <= 0;
      end else begin
          // ONLY capture valid math results written to real registers!
          if (rf_reg_write && rf_write_dest != 5'd0 && !stall) begin
              display_buffer <= rf_write_data;
          end
      end
  end
  assign latest_result = display_buffer;
  
  // -------- MEMORY-MAPPED I/O (MMIO) FOR LEDs -------- //
  always @(posedge clk) begin
      if (!reset) begin
          led_out <= 16'b0;
      end else begin
          // If the C-code tries to write to our magic address (0x00007000)...
          if (dmem_write_ready && dmem_write_address == 32'h00007000) begin
              // Intercept the data and physically route it to the LEDs!
              led_out <= dmem_write_data[15:0]; 
          end
      end
  end
endmodule