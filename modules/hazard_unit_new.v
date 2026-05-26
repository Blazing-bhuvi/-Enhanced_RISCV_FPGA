`timescale 1ns / 1ps

module hazard_unit_new (
    // Instruction Opcode to prevent phantom stalls
    input [6:0] id_opcode,       // <--- NEW INPUT

    // Data Hazard Inputs
    input [4:0] id_rs1,
    input [4:0] id_rs2,
    input [4:0] ex_rs1,
    input [4:0] ex_rs2,
    input [4:0] ex_rd,
    input [4:0] mem_rd,
    input [4:0] wb_rd,
    input       ex_reg_write,
    input       mem_reg_write,
    input       wb_reg_write,
    input       ex_mem_to_reg,   // High if EX is a LOAD
    input       mem_mem_to_reg,  // High if MEM is a LOAD

    // Control Hazard Inputs
    input       branch_taken,    // From EX resolution

    // Structural Hazard Inputs
    input       ex_busy,         // From multi-cycle units

    // Outputs
    output reg [1:0] forward_a,  
    output reg [1:0] forward_b,
    output           stall_if,
    output           stall_id,
    output           flush_id,
    output           flush_ex
);

    // -- 1. Data Hazard: Forwarding Logic (EX Stage) --
    always @(*) begin
        // Forward A
        if (mem_reg_write && (mem_rd != 0) && (mem_rd == ex_rs1))
            forward_a = 2'b01;
        else if (wb_reg_write && (wb_rd != 0) && (wb_rd == ex_rs1))
            forward_a = 2'b10;
        else
            forward_a = 2'b00;

        // Forward B
        if (mem_reg_write && (mem_rd != 0) && (mem_rd == ex_rs2))
            forward_b = 2'b01;
        else if (wb_reg_write && (wb_rd != 0) && (wb_rd == ex_rs2))
            forward_b = 2'b10;
        else
            forward_b = 2'b00;
    end

    // -- 2. Phantom Stall Prevention (Register Usage Decoding) --
    // Only flag true if the instruction type physically reads from these registers.
    // Includes standard RISC-V opcodes + your custom DSP macro opcode (7'b0001011 / 0x0B)
    wire id_uses_rs1 = (id_opcode == 7'b0110011) || // R-type
                       (id_opcode == 7'b0010011) || // I-type
                       (id_opcode == 7'b0000011) || // Load
                       (id_opcode == 7'b0100011) || // Store
                       (id_opcode == 7'b1100011) || // Branch
                       (id_opcode == 7'b1100111) || // JALR
                       (id_opcode == 7'b0001011);   // Custom DSP

    wire id_uses_rs2 = (id_opcode == 7'b0110011) || // R-type
                       (id_opcode == 7'b0100011) || // Store
                       (id_opcode == 7'b1100011) || // Branch
                       (id_opcode == 7'b0001011);   // Custom DSP

    // -- 3. Data Hazard: Load-Use Stall --
    // Stalls ONLY if the specific register is actually used by the ID instruction.
    wire load_use_stall = ex_mem_to_reg && (ex_rd != 0) &&
                          ((id_uses_rs1 && (ex_rd == id_rs1)) || 
                           (id_uses_rs2 && (ex_rd == id_rs2)));

    // -- 4. Structural Hazard: Multi-cycle Units --
    wire structural_stall = ex_busy;

    // -- Pipeline Control Signals --
    assign stall_if = load_use_stall || structural_stall;
    assign stall_id = load_use_stall || structural_stall;
    
    assign flush_id = branch_taken;
    assign flush_ex = branch_taken || load_use_stall;

endmodule