MEMORY {
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 16K
}

SECTIONS {
    .text : { 
        *(.text.init) 
        *(.text*) 
    } > RAM

    .rodata : { 
        . = ALIGN(4);
        *(.rodata*) 
        *(.srodata*)
    } > RAM

    .data : { 
        . = ALIGN(4);
        *(.data*) 
        *(.sdata*) 
    } > RAM

    .bss : { 
        . = ALIGN(4);
        *(.bss*) 
        *(.sbss*) 
    } > RAM
}