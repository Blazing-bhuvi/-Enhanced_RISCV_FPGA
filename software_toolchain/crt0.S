.section .text.init
.global _start

_start:
    /* Set Stack Pointer to the top of 4KB DMEM (0x2000 + 0x1000 = 0x3000) */
    li sp, 0x3000  

    /* Jump to the C program */
    call main      

    /* C puts the 'return' value in register a0 (x10). 
       We move it to x1 to trigger your FPGA's 7-segment display buffer! */
    mv x1, a0      

halt:
    /* Safe infinite loop to end simulation/execution */
    j halt