`timescale 1ns / 1ps

module tb_system_final;

    reg clk;
    reg reset;

    // Core Wires
    wire exception;
    wire [31:0] pc_out;
    wire [31:0] inst_mem_address, inst_mem_read_data;
    wire inst_mem_is_ready;
    wire [31:0] dmem_read_address, dmem_read_data_temp, dmem_write_address, dmem_write_data;
    wire dmem_read_ready, dmem_write_ready;
    wire [3:0]  dmem_write_byte;
    wire [31:0] latest_result;
    
    // --- MMIO Wires ---
    wire [15:0] sim_led_out; 

    wire icache_stall, dcache_stall;
    wire pipeline_stall = icache_stall | dcache_stall;

    // Cache Wires
    wire icache_hit, imem_read, imem_valid;
    wire [31:0] imem_addr, imem_rdata;
    wire dcache_hit, dmem_read_o, dmem_write_o, dmem_valid;
    wire [31:0] dmem_addr_o, dmem_wdata_o, dmem_rdata_i;
    wire [31:0] dcache_addr = dmem_write_ready ? dmem_write_address : dmem_read_address;

    // Caches & Instruction Memory
    i_cache icache (
        .clk(clk), .reset(reset),
        .pc_i(inst_mem_address), .instr_o(inst_mem_read_data),
        .hit_o(icache_hit), .stall_o(icache_stall),
        .mem_read_o(imem_read), .mem_addr_o(imem_addr),
        .mem_data_i(imem_rdata), .mem_valid_i(imem_valid)
    );

    main_memory #(.MEM_SIZE(4096), .INIT_FILE("C:/Users/Bhuva/5_stage_pipeline_nexys/5_stage_pipeline_nexys.srcs/sources_1/imports/xsim/imem.hex")) main_imem (
        .clk(clk), .reset(~reset),
        .mem_read_i(imem_read), .mem_write_i(1'b0),
        .addr_i(imem_addr), .wdata_i(32'b0),
        .rdata_o(imem_rdata), .valid_o(imem_valid)
    );

    // --- THE TESTBENCH MEMORY FIREWALL ---
    // Protects physical RAM from being overwritten by LED or RGB updates during simulation
    wire is_mmio = (dmem_write_address == 32'h00007000) || (dmem_write_address == 32'h00007004);

    d_cache dcache (
        .clk(clk), .reset(reset),
        .addr_i(dcache_addr), .wdata_i(dmem_write_data),
        .rden_i(dmem_read_ready), 
        .wren_i(dmem_write_ready && !is_mmio), // <--- FIREWALL APPLIED!
        .rdata_o(dmem_read_data_temp), .hit_o(dcache_hit), .stall_o(dcache_stall),
        .mem_read_o(dmem_read_o), .mem_write_o(dmem_write_o),
        .mem_addr_o(dmem_addr_o), .mem_wdata_o(dmem_wdata_o),
        .mem_rdata_i(dmem_rdata_i), .mem_valid_i(dmem_valid)
    );

    main_memory #(.MEM_SIZE(4096), .INIT_FILE("C:/Users/Bhuva/5_stage_pipeline_nexys/5_stage_pipeline_nexys.srcs/sources_1/imports/xsim/dmem.hex")) main_dmem (
        .clk(clk), .reset(~reset),
        .mem_read_i(dmem_read_o), .mem_write_i(dmem_write_o),
        .addr_i(dmem_addr_o), .wdata_i(dmem_wdata_o),
        .rdata_o(dmem_rdata_i), .valid_o(dmem_valid)
    );

    // THE CPU
    pipe_new DUT (
        .clk(clk), .reset(reset), .stall(pipeline_stall), .exception(exception), .pc_out(pc_out),
        .inst_mem_address(inst_mem_address), .inst_mem_is_valid(1'b1), .inst_mem_read_data(inst_mem_read_data), .inst_mem_is_ready(inst_mem_is_ready),
        .dmem_read_address(dmem_read_address), .dmem_read_ready(dmem_read_ready), .dmem_read_data_temp(dmem_read_data_temp), .dmem_read_valid(1'b1),
        .dmem_write_address(dmem_write_address), .dmem_write_ready(dmem_write_ready), .dmem_write_data(dmem_write_data), .dmem_write_byte(dmem_write_byte), .dmem_write_valid(1'b1),
        .latest_result(latest_result),
        .led_out(sim_led_out) 
    );

    // --- Performance Profiler ---
    integer total_cycles = 0;
    
    // Cache Stats
    integer i_cache_misses = 0, i_cache_hits = 0;
    integer d_cache_misses = 0, d_cache_hits = 0;
    reg icache_stall_d = 0, dcache_stall_d = 0;
    
    // Branch Prediction Stats
    integer bp_total = 0;
    integer bp_correct = 0;
    integer bp_miss = 0;

    always @(posedge clk) begin
        if (reset) begin
            total_cycles = total_cycles + 1;
            
            // 1. Evaluate Cache Performance
            icache_stall_d <= icache_stall;
            dcache_stall_d <= dcache_stall;
            
            if (icache_stall && !icache_stall_d) i_cache_misses = i_cache_misses + 1;
            else if (!icache_stall) i_cache_hits = i_cache_hits + 1;

            if (dcache_stall && !dcache_stall_d) d_cache_misses = d_cache_misses + 1;
            else if (!dcache_stall && (dmem_read_ready || dmem_write_ready)) d_cache_hits = d_cache_hits + 1;

            // 2. Evaluate Branch Prediction Performance
            // Tap into the EX stage: Only count when a branch is actively resolving and the pipeline isn't stalled!
            if (DUT.ex_stage.branch_i && !pipeline_stall) begin
                bp_total = bp_total + 1;
                
                if (DUT.ex_stage.actual_taken_o == DUT.ex_stage.predict_taken_i) begin
                    bp_correct = bp_correct + 1;
                    $display("[Cycle %0d] BP MATCH -> Predicted: %b | Actual: %b", total_cycles, DUT.ex_stage.predict_taken_i, DUT.ex_stage.actual_taken_o);
                end else begin
                    bp_miss = bp_miss + 1;
                    $display("[Cycle %0d] BP FLUSH -> Predicted: %b | Actual: %b (Pipeline Flushed!)", total_cycles, DUT.ex_stage.predict_taken_i, DUT.ex_stage.actual_taken_o);
                end
            end

            // 3. Detect the "DONE" MMIO Signal (RGB LED Trigger)
            // This safely intercepts the final C-code instruction to end the simulation!
            if (dmem_write_ready && dmem_write_address == 32'h00007004) begin
                
                // Wait 20 clock cycles to let the CPU enter the while(1) loop 
                // and push the final_display to the 7-segment buffer!
                repeat(20) @(posedge clk); 
                
                $display("\n====================================================");
                $display("       [UNIFIED DSP PIPELINE EXECUTION COMPLETE]    ");
                $display("====================================================");
                $display("Raw 32-Bit 7-Seg Output: 0x%08X", latest_result);
                $display("Raw 16-Bit MMIO LED Out: 0x%04X", sim_led_out);
                $display("----------------------------------------------------");
                $display("Phase Angle (7-Seg Top) : %0d Degrees", latest_result[31:16]);
                $display("Magnitude   (7-Seg Bot) : %0d", latest_result[15:0]);
                $display("Filtered Sum (MMIO LEDs): %0d", sim_led_out);
                $display("----------------------------------------------------");
                $display("Total Clock Cycles      : %0d", total_cycles);
                $display("----------------------------------------------------");
                
                // Calculate and format the exact percentages!
                $display("I-Cache Performance     : %0d Hits | %0d Misses (%.2f%% Hit Rate)", i_cache_hits, i_cache_misses, 
                         (i_cache_hits * 100.0) / (i_cache_hits + i_cache_misses));
                $display("D-Cache Performance     : %0d Hits | %0d Misses (%.2f%% Hit Rate)", d_cache_hits, d_cache_misses, 
                         (d_cache_hits * 100.0) / (d_cache_hits + d_cache_misses));
                $display("Branch Predictor        : %0d Correct | %0d Flushes (%.2f%% Accuracy)", bp_correct, bp_miss, 
                         (bp_total > 0) ? (bp_correct * 100.0) / bp_total : 0.0);
                
                $display("====================================================\n");
                $finish;
            end
        end
    end

    // Clock & Reset
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    initial begin
        reset = 0;
        #20; reset = 1;
        #500000; 
        $display("Simulation Timeout Reached.");
        $finish;
    end
endmodule