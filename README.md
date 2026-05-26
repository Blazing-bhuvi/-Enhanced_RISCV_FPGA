# 5-Stage RISC-V DSP SoC with Custom Hardware Accelerators

This repository contains the hardware and software implementation of a custom 32-bit RISC-V System-on-Chip (SoC). Designed specifically for high-speed digital signal processing, the architecture features a fully unrolled 5-stage pipeline, an L1 cache hierarchy, and specialized hardware accelerators. Developed at the Department of Computer Science and Engineering at the Indian Institute of Technology Guwahati (IITG), this project bridges the gap between low-level hardware design and bare-metal software optimization to create a highly efficient processing engine.

## Key Architectural Features

* 5-Stage RV32IM Pipeline: A classic Instruction Fetch (IF), Decode (ID), Execute (EX), Memory (MEM), and Writeback (WB) architecture with full hazard detection and data forwarding.
* Custom DSP Accelerators: Silicon-level Multiply-Accumulate (MAC), Square Root (SQRT), and CORDIC (Phase Angle) computational units integrated directly into the Execute stage. These are accessed via custom RISC-V assembly (.insn) macros for maximum throughput.
* L1 Cache Hierarchy: Fully independent, 4KB Block-RAM backed Instruction and Data caches that consistently achieve over 99% hit rates on localized DSP loops.
* Dynamic Branch Prediction: An integrated Branch Target Buffer (BTB) that predicts loop behavior, minimizing costly pipeline flushes during repetitive array computations.
* Bare-Metal Bootloader: A custom Python-to-Hardware UART bootloader that safely halts the CPU, writes firmware directly into BRAM via a physical multiplexer, and executes a clean reboot of the processor.
* Robust MMIO & Profiling: A Memory-Mapped I/O ecosystem featuring a 3-state hardware FSM for UART transmission, real-time 7-segment display drivers, and an isolatable hardware profiler that precisely tracks clock cycles and cache statistics.

## Repository Structure

* top_fpga.v - The top-level Verilog wrapper instantiating the CPU core, memory multiplexers, UART modules, MMIO logic, and display drivers.
* filter.c - The core bare-metal C program demonstrating signal filtering, vector magnitude calculation, and noise elimination using the custom hardware macros.
* link.ld - A highly compact linker script engineered to safely pack .text and .rodata sections into a dense memory block, preventing bootloader memory wrap-around exceptions.
* Makefile - Build automation utilizing the bare-metal riscv-none-elf- compiler toolchain.
* flash.py - The Python-based serial flashing utility that communicates with the FPGA's bootloader.
* bin2hex.py - A utility for converting compiled binaries into hex formats for Vivado simulation and hardware initialization.

## Prerequisites

To build and run this project, you will need the following hardware and software tools:

* Hardware: Digilent Nexys A7 (Artix-7) FPGA Board.
* Synthesis: Xilinx Vivado (2020.1 or newer recommended).
* Software Toolchain: riscv-none-elf-gcc compiler toolchain.
* Python Packages: pyserial (for executing the flash.py bootloader script).

## Configuration & Environment Setup

Before compiling, flashing, or simulating, you must update the following files to match your local computer's environment:

1. Makefile (COM Port): Open Makefile and change PORT = COM4 to the port assigned to your physical FPGA board (e.g., COM3 on Windows, or /dev/ttyUSB0 on Linux/Mac).
2. Makefile (Compiler): If your RISC-V toolchain uses a different prefix, update the TOOLCHAIN = riscv-none-elf- line.
3. Makefile (OS Commands): The make clean command currently uses the Windows del /Q /F syntax. If you are on Linux or macOS, change this to rm -f $(ELF) $(BIN).
4. Testbench (Absolute Paths): Open tb_system_final.v. On lines 40 and 62, the .INIT_FILE parameters use hardcoded absolute paths (e.g., C:/Users/.../imem.hex). You must change these to the exact absolute paths where imem.hex and dmem.hex are located on your local machine before running the Vivado behavioral simulation.

## Hardware Controls & Switches

To properly evaluate the physical hardware, please note the following Nexys A7 board configurations:

* SW[0] (Execution Mode): 
  * UP (Automatic Mode): The processor runs continuously based on the selected clock speed.
  * DOWN (Manual Mode): Pauses continuous execution, allowing for manual, step-by-step pipeline debugging.
* SW[1] (Bootloader Select): 
  * UP (Program Mode): Halts the CPU and connects the memory bus directly to the UART bootloader for flashing firmware. 
  * DOWN (Run Mode): Disconnects the bootloader and hands control of the memory bus back to the CPU.
* SW[2] (Clock Speed): 
  * UP (Fast Clock / Turbo): Runs the CPU at 100 MHz. Note: Hardware execution statistics and array outputs will only print to the serial terminal when the processor is running in Fast Clock mode.
  * DOWN (Slow Clock): Slows the CPU down for visual debugging on the LEDs and 7-segment display. Terminal printing is physically paused to prevent display flickering.
* CPU Reset Button: Re-initializes the pipeline and restarts the C program. Note: The reset button is hardware-interlocked and will only function when the system is in Run Mode (SW[1] DOWN) and Automatic Mode (SW[0] UP).

## Build and Flash Instructions

1. Synthesize Hardware: Open Vivado, generate the bitstream using top_fpga.v as the top module, and program the Nexys board.
2. Compile the Software: Open a terminal in the software_toolchain directory and compile the firmware by running:
   make clean
   make
3. Flash to FPGA: Ensure the physical SW[1] switch is flipped UP (Program Mode), then run:
   make flash
4. Execute and Monitor: Follow the terminal prompts, flip SW[1] DOWN (Automatic/Run Mode) to start the CPU. Ensure the Fast Clock switch is enabled to view the performance statistics on the serial monitor.

## Team & Contributions

This project was architected and developed by:

* Bhuvan Chilukuti: 
  * Hardware Modules: 5-Stage Pipeline Integration, Pipeline Registers, UART Module.
  * Software Toolchain & Firmware: filter.c, link.ld, Makefile, flash.py, bin2hex.py, crt0.S. Lead Systems Integrator bridging the bare-metal software with the physical hardware pipeline.
* Akash Reddy: Hardware Square Optimization, Division Unit, Finite State Machines (FSM) for Mul/Div Units.
* Chetan Srirama: Hardware Multiplication Unit, Dynamic Branch Predictor, Pipeline Hazard Detection & Resolution.
* Karthik Macharla: Hardware MAC Unit, L1 Instruction Cache, L1 Data Cache.
* Venu Kummari: Hardware CORDIC Unit, Square Root Unit, Hardware Performance Counters.