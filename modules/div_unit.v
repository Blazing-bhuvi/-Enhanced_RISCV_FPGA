// =============================================================================
// div_unit.v  –  Integer + Fixed-Point Division Unit
//
// Supported operations (one-hot control signals):
//   divu  – unsigned integer division        val = a / b
//   div   – signed integer division          val = a / b  (quotient)
//   remu  – unsigned integer remainder       val = a % b
//   rem   – signed integer remainder         val = a % b  (Euclidean, r >= 0)
//   fdiv  – signed fixed-point Q16.16 div   val = a / b  (Q16.16 result)
//
// Ports added vs original:
//   input  fdiv      – trigger fixed-point division
//   output ovf       – overflow flag (fdiv only; integer ops leave it 0)
//
// Fixed-point format (fdiv):
//   WIDTH=32, FBITS=WIDTH/2=16 → Q16.16
//   Both a and b are interpreted as signed Q16.16 inputs.
//   Result val is signed Q16.16.
//   Algorithm: non-restoring with Gaussian rounding, identical to reference.
//   Iterations: WIDTHU + FBITS = 31 + 16 = 47 cycles.
//
// Integer format (div/divu/rem/remu):
//   Restoring division, WIDTH iterations.
//   Euclidean remainder: 0 <= r < |b| always.
// =============================================================================

module div_unit
#(
    parameter WIDTH = 32,
    parameter FBITS = WIDTH / 2   // fractional bits for fdiv (Q16.16 default)
)
(
    input                   clk,
    input                   reset,
    input                   start,
    input                   div,    // Signed integer division
    input                   divu,   // Unsigned integer division
    input                   rem,    // Signed integer remainder
    input                   remu,   // Unsigned integer remainder
    input                   fdiv,   // Signed fixed-point division (Q16.16)

    input      [WIDTH-1:0]  a,
    input      [WIDTH-1:0]  b,

    output reg              busy,
    output reg              done,
    output reg              valid,
    output reg              dbz,
    output reg              ovf,    // overflow (fdiv only)
    output reg              stall,
    output reg [WIDTH-1:0]  val,
    output reg [WIDTH-1:0]  remainder
);

    // =========================================================================
    // Shared constants
    // =========================================================================
    localparam WIDTHU   = WIDTH - 1;                    // unsigned working width for fdiv
    localparam FBITSW   = (FBITS == 0) ? 1 : FBITS;    // safe non-zero width
    localparam ITER     = WIDTHU + FBITS;               // fdiv iteration count
    localparam SMALLEST = {1'b1, {WIDTHU{1'b0}}};      // most-negative number

    // =========================================================================
    // INTEGER division registers
    // =========================================================================
    reg [WIDTH-1:0]       b_abs;
    reg [WIDTH-1:0]       int_quo;
    reg [WIDTH:0]         int_acc;
    reg [$clog2(WIDTH):0] int_count;
    reg                   a_neg, b_neg, is_signed, want_rem;

    // Combinational temporaries for integer path
    reg [WIDTH:0]   sub_res;
    reg [WIDTH-1:0] q_out;
    reg [WIDTH-1:0] r_out;

    // =========================================================================
    // FIXED-POINT division registers  (mirrors reference div.v exactly)
    // =========================================================================
    // fp_state encoding
    localparam FP_IDLE  = 3'd0;
    localparam FP_INIT  = 3'd1;
    localparam FP_CALC  = 3'd2;
    localparam FP_ROUND = 3'd3;
    localparam FP_SIGN  = 3'd4;

    reg [2:0]              fp_state;
    reg [$clog2(ITER+1):0] fp_i;        // iteration counter (ITER+1 headroom)
    reg                    fp_a_sig, fp_b_sig, fp_sig_diff;
    reg [WIDTHU-1:0]       fp_au, fp_bu;
    reg [WIDTHU-1:0]       fp_quo;
    reg [WIDTHU:0]         fp_acc;      // 1 bit wider than WIDTHU
    reg                    fp_ovf;

    // Combinational next-state signals for fdiv (mirrors reference exactly)
    reg [WIDTHU-1:0] fp_quo_next;
    reg [WIDTHU:0]   fp_acc_next;

    always @(*) begin
        if (fp_acc >= {1'b0, fp_bu}) begin
            fp_acc_next = fp_acc - fp_bu;
            {fp_acc_next, fp_quo_next} = {fp_acc_next[WIDTHU-1:0], fp_quo, 1'b1};
        end else begin
            {fp_acc_next, fp_quo_next} = {fp_acc, fp_quo} << 1;
        end
    end

    // =========================================================================
    // Stall: start arrives while already busy
    // =========================================================================
    always @(*) begin
        stall = (start && busy);
    end

    // =========================================================================
    // Main sequential logic
    // =========================================================================
    always @(posedge clk) begin
        if (reset) begin
            busy      <= 0;
            done      <= 0;
            valid     <= 0;
            dbz       <= 0;
            ovf       <= 0;
            val       <= 0;
            remainder <= 0;
            int_count <= 0;
            a_neg     <= 0;
            b_neg     <= 0;
            is_signed <= 0;
            want_rem  <= 0;
            fp_state  <= FP_IDLE;
            fp_i      <= 0;
            fp_a_sig  <= 0;
            fp_b_sig  <= 0;
            fp_sig_diff <= 0;
            fp_au     <= 0;
            fp_bu     <= 0;
            fp_quo    <= 0;
            fp_acc    <= 0;
            fp_ovf    <= 0;

        end else begin
            done <= 0;  // default: pulse only

            // =================================================================
            // START – accept new operation when idle
            // =================================================================
            if (start && (div || divu || rem || remu || fdiv) && !busy) begin

                ovf   <= 0;
                valid <= 0;

                // -------------------------------------------------------------
                // FDIV start
                // -------------------------------------------------------------
                if (fdiv) begin
                    if (b == 0) begin
                        dbz   <= 1;
                        ovf   <= 0;
                        done  <= 1;
                        valid <= 1;
                        val   <= {WIDTH{1'b1}};
                        remainder <= 0;
                    end else if (a == SMALLEST || b == SMALLEST) begin
                        // Overflow: most-negative number can't be represented
                        dbz   <= 0;
                        ovf   <= 1;
                        done  <= 1;
                        valid <= 1;
                        val   <= {WIDTH{1'b1}};
                        remainder <= 0;
                    end else begin
                        busy      <= 1;
                        dbz       <= 0;
                        fp_a_sig  <= a[WIDTH-1];
                        fp_b_sig  <= b[WIDTH-1];
                        fp_sig_diff <= a[WIDTH-1] ^ b[WIDTH-1];
                        // Absolute values (strip sign bit, negate if negative)
                        fp_au <= a[WIDTH-1] ? -a[WIDTHU-1:0] : a[WIDTHU-1:0];
                        fp_bu <= b[WIDTH-1] ? -b[WIDTHU-1:0] : b[WIDTHU-1:0];
                        fp_state <= FP_INIT;
                    end

                // -------------------------------------------------------------
                // INTEGER start (div / divu / rem / remu)
                // -------------------------------------------------------------
                end else begin
                    if (b == 0) begin
                        dbz       <= 1;
                        done      <= 1;
                        valid     <= 1;
                        val       <= {WIDTH{1'b1}};
                        remainder <= a;
                    end else begin
                        busy      <= 1;
                        dbz       <= 0;
                        int_count <= 0;
                        is_signed <= (div || rem);
                        want_rem  <= (rem || remu);
                        a_neg     <= a[WIDTH-1] && (div || rem);
                        b_neg     <= b[WIDTH-1] && (div || rem);
                        b_abs     <= (b[WIDTH-1] && (div || rem)) ? (~b + 1) : b;
                        int_acc   <= {(WIDTH+1){1'b0}};
                        int_quo   <= (a[WIDTH-1] && (div || rem)) ? (~a + 1) : a;
                    end
                end

            // =================================================================
            // BUSY – fixed-point state machine
            // =================================================================
            end else if (busy && fp_state != FP_IDLE) begin

                case (fp_state)

                    // ----------------------------------------------------------
                    FP_INIT: begin
                        fp_state <= FP_CALC;
                        fp_ovf   <= 0;
                        fp_i     <= 0;
                        // Initialise: load au into top of {acc,quo}, shift left 1
                        {fp_acc, fp_quo} <= {{WIDTHU{1'b0}}, fp_au, 1'b0};
                    end

                    // ----------------------------------------------------------
                    FP_CALC: begin
                        // Overflow check at iteration WIDTHU-1
                        if (fp_i == WIDTHU - 1 &&
                            fp_quo_next[WIDTHU-1 -: FBITSW] != 0) begin
                            // Integer part overflows
                            busy     <= 0;
                            done     <= 1;
                            ovf      <= 1;
                            valid    <= 1;
                            val      <= {WIDTH{1'b1}};
                            remainder <= 0;
                            fp_state <= FP_IDLE;
                        end else begin
                            if (fp_i == ITER - 1) fp_state <= FP_ROUND;
                            fp_i   <= fp_i + 1;
                            fp_acc <= fp_acc_next;
                            fp_quo <= fp_quo_next;
                        end
                    end

                    // ----------------------------------------------------------
                    FP_ROUND: begin  // Gaussian (banker's) rounding
                        fp_state <= FP_SIGN;
                        if (fp_quo_next[0] == 1'b1) begin
                            // Next digit would be 1 → consider rounding up
                            if (fp_quo[0] == 1'b1 ||
                                fp_acc_next[WIDTHU:1] != 0) begin
                                fp_quo <= fp_quo + 1;
                            end
                        end
                    end

                    // ----------------------------------------------------------
                    FP_SIGN: begin  // Apply sign, write output
                        fp_state <= FP_IDLE;
                        busy     <= 0;
                        done     <= 1;
                        valid    <= 1;
                        ovf      <= 0;
                        remainder <= 0;
                        // Apply sign if quotient is non-zero
                        if (fp_quo != 0)
                            val <= fp_sig_diff ? {1'b1, -fp_quo}
                                               : {1'b0,  fp_quo};
                        else
                            val <= 0;
                    end

                    default: fp_state <= FP_IDLE;
                endcase

            // =================================================================
            // BUSY – integer restoring division (one step per clock)
            // =================================================================
            end else if (busy) begin

                sub_res = {int_acc[WIDTH-1:0], int_quo[WIDTH-1]} - {1'b0, b_abs};

                if (sub_res[WIDTH]) begin
                    // Subtraction would go negative → restore
                    int_acc <= {1'b0, int_acc[WIDTH-1:0], int_quo[WIDTH-1]};
                    int_quo <= {int_quo[WIDTH-2:0], 1'b0};
                end else begin
                    int_acc <= {1'b0, sub_res[WIDTH-1:0]};
                    int_quo <= {int_quo[WIDTH-2:0], 1'b1};
                end

                if (int_count == WIDTH - 1) begin
                    busy  <= 0;
                    done  <= 1;
                    valid <= 1;

                    q_out = {int_quo[WIDTH-2:0], ~sub_res[WIDTH]};
                    r_out = sub_res[WIDTH]
                            ? {int_acc[WIDTH-1:0], int_quo[WIDTH-1]}
                            : sub_res[WIDTH-1:0];

                    // T-division sign correction:
                    //   quotient  is negative when inputs have opposite signs
                    //   remainder has the same sign as the dividend (a)
                    if (is_signed) begin
                        if (a_neg ^ b_neg) q_out = ~q_out + 1; // negate quotient
                        if (a_neg)         r_out = ~r_out + 1; // negate remainder
                    end
                    // Invariant: a = q*b + r,  sign(r) == sign(a)

                    if (want_rem) begin
                        val       <= r_out;
                        remainder <= q_out;
                    end else begin
                        val       <= q_out;
                        remainder <= r_out;
                    end

                end else begin
                    int_count <= int_count + 1;
                end

            end // busy integer
        end // !reset
    end // always

endmodule