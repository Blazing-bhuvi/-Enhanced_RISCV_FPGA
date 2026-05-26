//  OPCODE and parameter definitions

`define OPCODE      6:0
`define FUNC3       14:12
`define SUBTYPE     30
`define RD          11:7
`define RS1         19:15
`define RS2         24:20
`define FUNC7       31:25

localparam [ 6: 0] FUNC7_M = 7'b0000001;

localparam  [31: 0] NOP        = 32'h0000_0013;     // addi x0, x0, 0

// OPCODE, INST[6:0]
localparam  [ 6: 0] LUI     = 7'b0110111,        // U-type
                    JAL     = 7'b1101111,        // J-type
                    JALR    = 7'b1100111,        // I-type
                    BRANCH  = 7'b1100011,        // B-type
                    LOAD    = 7'b0000011,        // I-type
                    STORE   = 7'b0100011,        // S-type
                    ARITHI  = 7'b0010011,        // I-type
                    ARITHR  = 7'b0110011,        // R-type
                    CUSTOM  = 7'b0001011;        // Custom DSP Extensions

// FUNC3 for Custom extensions (OPCODE == CUSTOM)
localparam  [ 2: 0] MAC_ACC   = 3'b000,
                    MAC_CLR   = 3'b001,
                    SQ_OP     = 3'b010,
                    SQRT_OP   = 3'b011,
                    CORDIC_OP = 3'b100;

// FUNC3, INST[14:12], INST[6:0] = 7'b1100011
localparam  [ 2: 0] BEQ     = 3'b000,
                    BNE     = 3'b001,
                    BLT     = 3'b100,
                    BGE     = 3'b101,
                    BLTU    = 3'b110,
                    BGEU    = 3'b111;

// FUNC3, INST[14:12], INST[6:0] = 7'b0000011
localparam  [ 2: 0] LB      = 3'b000,
                    LH      = 3'b001,
                    LW      = 3'b010,
                    LBU     = 3'b100,
                    LHU     = 3'b101;

// FUNC3, INST[14:12], INST[6:0] = 7'b0100011
localparam  [ 2: 0] SB      = 3'b000,
                    SH      = 3'b001,
                    SW      = 3'b010;

// FUNC3, INST[14:12], INST[6:0] = 7'b0110011, 7'b0010011
localparam  [ 2: 0] ADD     = 3'b000,    
                    SLL     = 3'b001,
                    SLT     = 3'b010,
                    SLTU    = 3'b011,
                    XOR     = 3'b100,
                    SR      = 3'b101,    
                    OR      = 3'b110,
                    AND     = 3'b111;

// RV32M FUNC3, OPCODE = 7'b0110011, FUNC7 = 7'b0000001
localparam  [ 2: 0] MUL     = 3'b000, 
                    MULH    = 3'b001, 
                    MULHSU  = 3'b010, 
                    MULHU   = 3'b011, 
                    DIV     = 3'b100, 
                    DIVU    = 3'b101, 
                    REM     = 3'b110, 
                    REMU    = 3'b111;