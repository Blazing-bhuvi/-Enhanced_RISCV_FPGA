# --- Toolchain Setup ---
TOOLCHAIN = riscv-none-elf-
CC      = $(TOOLCHAIN)gcc
OBJCOPY = $(TOOLCHAIN)objcopy

# --- Compiler Flags ---
# We are now explicitly telling GCC to use your custom link.ld script!
CFLAGS = -march=rv32im -mabi=ilp32 -O1 -nostdlib -ffreestanding -T link.ld

# --- User Variables ---
SRC  = filter.c
ELF  = filter.elf
BIN  = filter.bin
PORT = COM4

all: $(BIN)

$(ELF): $(SRC)
	$(CC) $(CFLAGS) -o $(ELF) $(SRC)

$(BIN): $(ELF)
	$(OBJCOPY) -O binary $(ELF) $(BIN)

flash: $(BIN)
	python flash.py $(PORT) $(BIN)

clean:
	del /Q /F $(ELF) $(BIN)