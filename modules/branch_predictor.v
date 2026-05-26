`timescale 1ns / 1ps

module branch_predictor #(
    parameter INDEX_BITS = 6 // 64 entries in the BHT
)(
    input wire clk,
    input wire rst,
    
    // Fetch Stage: Prediction Interface
    input wire [31:0] fetch_pc,
    output wire predict_taken,
    
    // Execute Stage: Update Interface
    input wire [31:0] update_pc,
    input wire update_en,       // High if instruction is a branch
    input wire actual_taken     // 1 if branch was taken, 0 if not
);

    // 2-bit states
    localparam STRONGLY_NOT_TAKEN = 2'b00;
    localparam WEAKLY_NOT_TAKEN   = 2'b01;
    localparam WEAKLY_TAKEN       = 2'b10;
    localparam STRONGLY_TAKEN     = 2'b11;

    // Branch History Table (BHT)
    // 2-bit counter for each entry
    reg [1:0] bht [(1<<INDEX_BITS)-1:0];
    
    // Extract index from PCs (ignoring lower 2 bits due to 4-byte alignment)
    wire [INDEX_BITS-1:0] fetch_idx = fetch_pc[INDEX_BITS+1:2];
    wire [INDEX_BITS-1:0] update_idx = update_pc[INDEX_BITS+1:2];

    integer i;

    // Read logic (Combinational prediction)
    // Predict taken if counter is 10 or 11
    assign predict_taken = (bht[fetch_idx] >= WEAKLY_TAKEN);

    // Write logic (Sequential update)
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // Initialize to Weakly Not Taken (or Strongly Not Taken)
            for (i = 0; i < (1<<INDEX_BITS); i = i + 1) begin
                bht[i] <= WEAKLY_NOT_TAKEN;
            end
        end else if (update_en) begin
            // Saturating counter logic
            if (actual_taken) begin
                if (bht[update_idx] != STRONGLY_TAKEN)
                    bht[update_idx] <= bht[update_idx] + 1'b1;
            end else begin
                if (bht[update_idx] != STRONGLY_NOT_TAKEN)
                    bht[update_idx] <= bht[update_idx] - 1'b1;
            end
        end
    end
endmodule