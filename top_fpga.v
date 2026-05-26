`timescale 1ns / 1ps

module top_fpga (
    input  wire clk_100mhz,  
    input  wire btnC,        
    input  wire btnU,        
    input  wire [2:0] sw,    
    output wire [15:0] led,  
    output reg  [6:0] seg,   
    output reg  [7:0] an,    
    output wire led16_b, led16_g, led16_r,
    input  wire uart_rx_pin, 
    output wire uart_tx_pin  
);

    // ----------------------------------------------------
    // 1. CLOCK GENERATION & TURBO GEARBOX
    // ----------------------------------------------------
    reg [24:0] clk_counter = 0;
    reg slow_clk = 0;
    always @(posedge clk_100mhz) begin
        if (clk_counter >= 250000 - 1) begin 
            slow_clk <= ~slow_clk; clk_counter <= 0;
        end else clk_counter <= clk_counter + 1;
    end

    reg slow_clk_d = 0; reg btnU_d1 = 0, btnU_d2 = 0;
    always @(posedge clk_100mhz) begin
        slow_clk_d <= slow_clk; btnU_d1 <= btnU; btnU_d2 <= btnU_d1;
    end
    wire auto_pulse   = slow_clk && !slow_clk_d;
    wire manual_pulse = btnU_d1  && !btnU_d2;

    reg cpu_clk_reg = 0;
    always @(posedge clk_100mhz) begin
        if (sw[1]) cpu_clk_reg <= 0; 
        else if (sw[2]) cpu_clk_reg <= ~cpu_clk_reg; 
        else if (sw[0] ? auto_pulse : manual_pulse) cpu_clk_reg <= ~cpu_clk_reg;
    end
    wire cpu_clk = sw[2] ? clk_100mhz : cpu_clk_reg;

    // ----------------------------------------------------
    // 2. THE DECOUPLED RESET DOMAINS
    // ----------------------------------------------------
    reg rst_s1 = 0, rst_s2 = 0;
    always @(posedge clk_100mhz) begin rst_s1 <= btnC; rst_s2 <= rst_s1; end
    wire physical_reset = rst_s2; 
    wire periph_reset = physical_reset;
    wire boot_cpu_rst; 
    wire system_resetn = ~(physical_reset | boot_cpu_rst); 

    // ----------------------------------------------------
    // 3. BOOTLOADER & UART RX
    // ----------------------------------------------------
    wire [7:0] rx_data; wire rx_valid;
    uart_rx rx_inst (.clk(clk_100mhz), .reset(periph_reset), .rx_in(uart_rx_pin), .data(rx_data), .valid(rx_valid));

    wire [31:0] boot_addr, boot_data; wire boot_wen;
    bootloader bl_inst (
        .clk(clk_100mhz), .reset(periph_reset), .program_mode_sw(sw[1]),
        .rx_data(rx_data), .rx_valid(rx_valid),
        .mem_waddr(boot_addr), .mem_wdata(boot_data), .mem_wen(boot_wen), .cpu_reset(boot_cpu_rst)
    );

    // ----------------------------------------------------
    // 4. THE SYSTEM-ON-CHIP 
    // ----------------------------------------------------
    wire [31:0] pc, i_addr, i_data, d_addr_r, d_addr_w, d_wdata, d_rdata_t;
    wire ic_stall, dc_stall, dr_ready, dw_ready;
    wire ic_hit_wire, dc_hit_wire;

    wire ic_read, ic_valid; wire [31:0] ic_addr, ic_rdata;
    i_cache icache (.clk(cpu_clk), .reset(system_resetn), .pc_i(i_addr), .instr_o(i_data), .stall_o(ic_stall), .mem_read_o(ic_read), .mem_addr_o(ic_addr), .mem_data_i(ic_rdata), .mem_valid_i(ic_valid), .hit_o(ic_hit_wire));
    
    wire imem_clk = sw[1] ? clk_100mhz : cpu_clk;
    wire [31:0] imem_a = sw[1] ? boot_addr : ic_addr;
    wire [31:0] imem_d = sw[1] ? boot_data : 32'b0;
    wire imem_wen = sw[1] ? boot_wen : 1'b0;
    main_memory #(.MEM_SIZE(4096)) imem (.clk(imem_clk), .reset(periph_reset), .mem_read_i(!sw[1] && ic_read), .mem_write_i(imem_wen), .addr_i(imem_a), .wdata_i(imem_d), .rdata_o(ic_rdata), .valid_o(ic_valid));

    // EXTENDED MMIO RANGE TO COVER THE NEW TURBO SWITCH REGISTER
    wire is_mmio = (d_addr_w >= 32'h00007000 && d_addr_w <= 32'h00007034); 
    wire dc_read, dc_write, dc_valid; wire [31:0] dc_addr, dc_wdata, dc_rdata;
    d_cache dcache (.clk(cpu_clk), .reset(system_resetn), .addr_i(dw_ready ? d_addr_w : d_addr_r), .wdata_i(d_wdata), .rden_i(dr_ready), .wren_i(dw_ready && !is_mmio), .rdata_o(d_rdata_t), .stall_o(dc_stall), .mem_read_o(dc_read), .mem_write_o(dc_write), .mem_addr_o(dc_addr), .mem_wdata_o(dc_wdata), .mem_rdata_i(dc_rdata), .mem_valid_i(dc_valid), .hit_o(dc_hit_wire));
    
    wire dmem_clk = sw[1] ? clk_100mhz : cpu_clk;
    wire [31:0] dmem_a = sw[1] ? boot_addr : dc_addr;
    wire [31:0] dmem_d = sw[1] ? boot_data : dc_wdata;
    wire dmem_wen_actual = sw[1] ? boot_wen : dc_write;
    main_memory #(.MEM_SIZE(4096)) dmem (.clk(dmem_clk), .reset(periph_reset), .mem_read_i(sw[1] ? 1'b0 : dc_read), .mem_write_i(dmem_wen_actual), .addr_i(dmem_a), .wdata_i(dmem_d), .rdata_o(dc_rdata), .valid_o(dc_valid));

    // --- LIVE HARDWARE COUNTERS ---
    reg [31:0] ic_hits = 0, ic_misses = 0, dc_hits = 0, dc_misses = 0;
    reg [31:0] total_cycles = 0, bp_correct = 0, bp_flushes = 0;
    reg ic_stall_d = 0, dc_stall_d = 0;
    reg profiler_en = 0;
    reg seg_done = 0; 

    always @(posedge clk_100mhz) begin
        if (!system_resetn) profiler_en <= 0;
        else if (dw_ready && d_addr_w == 32'h00007030) profiler_en <= d_wdata[0];
    end

    always @(posedge cpu_clk) begin
        if (!system_resetn) begin
            ic_hits <= 0; ic_misses <= 0; dc_hits <= 0; dc_misses <= 0;
            total_cycles <= 0; bp_correct <= 0; bp_flushes <= 0;
            ic_stall_d <= 0; dc_stall_d <= 0;
        end else begin
            ic_stall_d <= ic_stall; 
            dc_stall_d <= dc_stall;

            if (profiler_en && !seg_done) begin
                total_cycles <= total_cycles + 1;
                if (ic_stall_d && !ic_stall) ic_misses <= ic_misses + 1;
                else if (!ic_stall && ic_hit_wire) ic_hits <= ic_hits + 1;

                if (dr_ready || dw_ready) begin
                    if (dc_stall_d && !dc_stall) dc_misses <= dc_misses + 1;
                    else if (!dc_stall && dc_hit_wire) dc_hits <= dc_hits + 1;
                end

                if (DUT.ex_stage.branch_i) begin
                    if (DUT.hz_flush_ex) bp_flushes <= bp_flushes + 1;
                    else bp_correct <= bp_correct + 1;
                end
            end
        end
    end

    // --- UART STATE MACHINE ---
    wire tx_busy; 
    reg tx_req = 0;
    reg [7:0] tx_data_latch = 0;
    reg [1:0] tx_state = 0;

    always @(posedge clk_100mhz) begin
        if (periph_reset) begin
            tx_req <= 0; tx_data_latch <= 0; tx_state <= 0;
        end else begin
            case (tx_state)
                0: begin 
                    if (dw_ready && d_addr_w == 32'h00007008 && !sw[1]) begin
                        tx_req <= 1; tx_data_latch <= d_wdata[7:0]; tx_state <= 1;
                    end
                end
                1: begin if (tx_busy) begin tx_req <= 0; tx_state <= 2; end end
                2: begin if (!tx_busy) tx_state <= 0; end
            endcase
        end
    end
    
    wire mmio_uart_busy = (tx_state != 0) || tx_busy;

    // --- FULL MMIO READ MULTIPLEXER ---
    wire [31:0] final_read_data = 
        (d_addr_r == 32'h0000700C) ? ic_hits :
        (d_addr_r == 32'h00007010) ? ic_misses :
        (d_addr_r == 32'h00007014) ? dc_hits :
        (d_addr_r == 32'h00007018) ? dc_misses :
        (d_addr_r == 32'h00007020) ? {31'b0, mmio_uart_busy} : 
        (d_addr_r == 32'h00007024) ? total_cycles :     
        (d_addr_r == 32'h00007028) ? bp_correct :       
        (d_addr_r == 32'h0000702C) ? bp_flushes :   
        (d_addr_r == 32'h00007034) ? {31'b0, sw[2]} : // NEW: Maps the physical Turbo switch to memory!    
        d_rdata_t;

    // --- RISC-V PIPELINE ---
    wire [31:0] res; wire [15:0] mmio_led;
    pipe_new DUT (.clk(cpu_clk), .reset(system_resetn), .stall(ic_stall | dc_stall), .pc_out(pc), .inst_mem_address(i_addr), .inst_mem_read_data(i_data), .inst_mem_is_ready(!ic_stall), .dmem_read_address(d_addr_r), .dmem_read_ready(dr_ready), .dmem_read_data_temp(final_read_data), .dmem_write_address(d_addr_w), .dmem_write_ready(dw_ready), .dmem_write_data(d_wdata), .latest_result(res), .led_out(mmio_led), .exception(led[15]), .inst_mem_is_valid(1'b1), .dmem_read_valid(1'b1), .dmem_write_valid(1'b1), .dmem_write_byte());

    uart_tx tx_inst (.clk(clk_100mhz), .reset(periph_reset), .data(tx_data_latch), .start(tx_req), .tx_out(uart_tx_pin), .busy(tx_busy));

    // ----------------------------------------------------
    // 6. DASHBOARD & DISPLAY
    // ----------------------------------------------------
    reg done = 0; reg [31:0] hw_7seg_data = 0; 
    always @(posedge clk_100mhz) begin
        if (!system_resetn) begin done <= 0; hw_7seg_data <= 0; seg_done <= 0; end 
        else if (dw_ready) begin
            if (d_addr_w == 32'h00007004) done <= 1;
            if (d_addr_w == 32'h0000701C) begin
                hw_7seg_data <= d_wdata; 
                seg_done <= 1;
            end
        end
    end

    assign led[14:12] = done ? 3'b000 : {ic_stall, dc_stall, (ic_stall|dc_stall)};
    assign led[10:0]  = mmio_led[10:0];

    wire [31:0] display_data = seg_done ? hw_7seg_data : res;

    reg [16:0] rf = 0; always @(posedge clk_100mhz) rf <= rf + 1;
    wire [2:0] dig = rf[16:14]; reg [3:0] v;
    
    always @(*) begin
        case(dig)
            0: begin v = display_data[3:0];   an = 8'b11111110; end
            1: begin v = display_data[7:4];   an = 8'b11111101; end
            2: begin v = display_data[11:8];  an = 8'b11111011; end
            3: begin v = display_data[15:12]; an = 8'b11110111; end
            4: begin v = display_data[19:16]; an = 8'b11101111; end
            5: begin v = display_data[23:20]; an = 8'b11011111; end
            6: begin v = display_data[27:24]; an = 8'b10111111; end
            7: begin v = display_data[31:28]; an = 8'b01111111; end
        endcase
    end
    
    always @(*) begin
        case(v)
            4'h0: seg = 7'b1000000; 4'h1: seg = 7'b1111001; 4'h2: seg = 7'b0100100; 4'h3: seg = 7'b0110000; 
            4'h4: seg = 7'b0011001; 4'h5: seg = 7'b0010010; 4'h6: seg = 7'b0000010; 4'h7: seg = 7'b1111000; 
            4'h8: seg = 7'b0000000; 4'h9: seg = 7'b0010000; 4'hA: seg = 7'b0001000; 4'hB: seg = 7'b0000011; 
            4'hC: seg = 7'b1000110; 4'hD: seg = 7'b0100001; 4'hE: seg = 7'b0000110; 4'hF: seg = 7'b0001110; default: seg = 7'b1111111;
        endcase
    end

    wire bp_flush = DUT.hz_flush_ex;
    wire bp_match = DUT.ex_stage.branch_i && !DUT.hz_flush_ex;
    
    assign led16_r = done ? rf[16]  : bp_flush;
    assign led16_g = done ? rf[15]  : bp_match;
    assign led16_b = done ? ~rf[16] : !(bp_flush || bp_match); 

endmodule