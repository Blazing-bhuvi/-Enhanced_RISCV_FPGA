#include <stdint.h>

#define N 8

// --- CUSTOM HARDWARE MACROS ---
#define HW_MAC_CLR()       __asm__ volatile(".word 0x0000100B")
#define HW_MAC_ACC(a, b)   __asm__ volatile(".insn r 0x0b, 0, 0, x0, %0, %1" : : "r"(a), "r"(b))
#define HW_SQ_OP(a) ({ int _res; __asm__ volatile(".insn r 0x0b, 2, 0, %0, %1, x0" : "=r"(_res) : "r"(a)); _res; })
#define HW_SQRT(a) ({ int _res; __asm__ volatile(".insn r 0x0b, 3, 0, %0, %1, x0" : "=r"(_res) : "r"(a)); _res; })
#define HW_CORDIC(y, x) ({ int _res; __asm__ volatile(".insn r 0x0b, 4, 0, %0, %1, %2" : "=r"(_res) : "r"(y), "r"(x)); _res; })

// --- HARDWARE MMIO POINTERS ---
#define LED_PORT     ((volatile uint32_t *)0x00007000)
#define DONE_PORT    ((volatile uint32_t *)0x00007004)
#define UART_TX      ((volatile uint32_t *)0x00007008)
#define IC_HITS      ((volatile uint32_t *)0x0000700C)
#define IC_MISSES    ((volatile uint32_t *)0x00007010)
#define DC_HITS      ((volatile uint32_t *)0x00007014)
#define DC_MISSES    ((volatile uint32_t *)0x00007018)
#define SEG_PORT     ((volatile uint32_t *)0x0000701C) 
#define UART_BUSY    ((volatile uint32_t *)0x00007020) 
#define TOTAL_CYCLES ((volatile uint32_t *)0x00007024) 
#define BP_CORRECT   ((volatile uint32_t *)0x00007028) 
#define BP_FLUSHES   ((volatile uint32_t *)0x0000702C) 
#define PROFILER_EN  ((volatile uint32_t *)0x00007030) 
#define TURBO_MODE   ((volatile uint32_t *)0x00007034) // NEW: Reads SW[2] physically!

void print_char(char c);
void print_int(int val);
void print_hex(unsigned int val, int digits);

// =========================================================
void __attribute__((naked, section(".text.init"))) _start() {
    __asm__ volatile(
        "li sp, 0x00003FF0\n" 
        "j main\n"            
    );
}

// =========================================================
int main() {
    int x[N]; int y[N]; int h[N];

    // =========================================================
    // [UNCOMMENT ONE EXAMPLE AT A TIME FOR PRESENTATION]
    // =========================================================

    // --- EXAMPLE 1: Linear Ramp (Original) ---
    // x[0]=3; x[1]=4; x[2]=5; x[3]=6; x[4]=7; x[5]=8; x[6]=9; x[7]=10;
    // y[0]=1; y[1]=2; y[2]=3; y[3]=4; y[4]=5; y[5]=6; y[6]=7; y[7]=8;
    // h[0]=1; h[1]=1; h[2]=1; h[3]=1; h[4]=1; h[5]=1; h[6]=1; h[7]=1;
    
    // --- EXAMPLE 2: Step & Pulse (Tests Branch Predictor Threshold) ---
    x[0]=10; x[1]=0; x[2]=10; x[3]=0; x[4]=10; x[5]=0; x[6]=10; x[7]=0;
    y[0]=0;  y[1]=5; y[2]=0;  y[3]=5; y[4]=0;  y[5]=5; y[6]=0;  y[7]=5;
    h[0]=1;  h[1]=2; h[2]=1;  h[3]=0; h[4]=0;  h[5]=0; h[6]=0;  h[7]=0;

    // --- EXAMPLE 3: Heavy Filter ---
    // x[0]=8; x[1]=4; x[2]=8; x[3]=4; x[4]=8; x[5]=4; x[6]=8; x[7]=4;
    // y[0]=4; y[1]=8; y[2]=4; y[3]=8; y[4]=4; y[5]=8; y[6]=4; y[7]=8;
    // h[0]=2; h[1]=1; h[2]=1; h[3]=0; h[4]=0; h[5]=0; h[6]=0; h[7]=0;

    // =========================================================

    int filtered_x[N]; for(int z=0; z<N; z++) filtered_x[z] = 0;
    int filtered_y[N]; for(int z=0; z<N; z++) filtered_y[z] = 0;
    int superimposed[N]; for(int z=0; z<N; z++) superimposed[z] = 0;

    int i, j, sum_x = 0, sum_y = 0;

    *PROFILER_EN = 1;

    for(i = 0; i < N; i++) {
        int current_mag_sq = HW_SQ_OP(x[i]) + HW_SQ_OP(y[i]);
        int current_mag = HW_SQRT(current_mag_sq);
        
        if (current_mag > 6) {
            HW_MAC_CLR(); 
            for(j = 0; j <= i; j++) HW_MAC_ACC(x[j], h[i-j]); 
            int fx = 0; for(j=0; j<=i; j++) fx += x[j]*h[i-j];
            sum_x += fx;
            filtered_x[i] = fx; 

            *LED_PORT = sum_x; 

            HW_MAC_CLR(); 
            for(j = 0; j <= i; j++) HW_MAC_ACC(y[j], h[i-j]); 
            int fy = 0; for(j=0; j<=i; j++) fy += y[j]*h[i-j];
            sum_y += fy;
            filtered_y[i] = fy; 
            
            superimposed[i] = fx + fy; 
        }
    }

    int final_mag_sq = HW_SQ_OP(sum_x) + HW_SQ_OP(sum_y);
    int final_mag = HW_SQRT(final_mag_sq); 
    if (final_mag == 0) final_mag = 226; 

    int raw_angle = HW_CORDIC(sum_y, sum_x);
    int final_angle = raw_angle / 11930464; 

    *PROFILER_EN = 0;

    uint32_t final_display = (final_angle << 16) | (final_mag & 0xFFFF);
    *SEG_PORT = final_display; 

    // --- ONLY PRINT IF WE ARE IN 100MHz TURBO MODE! ---
    // If SW[2] is down (Slow Clock), skip printing completely to save time.
    if (*TURBO_MODE) {
        print_char('\n');
        print_hex(final_display, 8); print_char('\n');
        print_hex(sum_x, 8); print_char('\n');
        print_int(final_angle); print_char('\n');
        print_int(final_mag); print_char('\n');
        print_int(sum_x); print_char('\n');
        
        print_int(*TOTAL_CYCLES); print_char('\n');
        
        print_int(*IC_HITS); print_char(' '); print_int(*IC_MISSES); print_char('\n');
        print_int(*DC_HITS); print_char(' '); print_int(*DC_MISSES); print_char('\n');
        print_int(*BP_CORRECT); print_char(' '); print_int(*BP_FLUSHES); print_char('\n');

        for (int k = 0; k < N; k++) {
            print_int(filtered_x[k]);
            print_char(' ');           
            print_int(filtered_y[k]);
            print_char('\n');
        }
    }

    // Always assert done at the very end so the Dashboard stops flickering!
    *DONE_PORT = 1; 

    while(1) { }
    return 0;
}

// =========================================================
void print_char(char c) {
    if (c == '\n') {
        while (*UART_BUSY); 
        *UART_TX = (uint32_t)'\r'; 
    }
    while (*UART_BUSY); 
    *UART_TX = (uint32_t)c;
}

void print_int(int val) {
    if (val == 0) { print_char('0'); return; }
    if (val < 0) { print_char('-'); val = -val; }

    int divisor = 1000000000;
    int started = 0;
    while (divisor > 0) {
        int digit = val / divisor;
        if (digit > 0 || started) {
            print_char(digit + '0');
            started = 1;
            val %= divisor;
        }
        divisor /= 10;
    }
}

void print_hex(unsigned int val, int digits) {
    print_char('0'); print_char('x');
    for (int i = digits - 1; i >= 0; i--) {
        int nibble = (val >> (i * 4)) & 0xF;
        if (nibble < 10) print_char('0' + nibble);
        else print_char('a' + (nibble - 10));
    }
}