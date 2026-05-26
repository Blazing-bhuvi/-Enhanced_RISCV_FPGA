import serial
import sys
import time

def main():
    if len(sys.argv) != 3:
        print("Usage: python flash.py <COM_PORT> <BINARY_FILE>")
        print("Example: python flash.py COM3 filter.bin")
        sys.exit(1)

    com_port = sys.argv[1]
    bin_file = sys.argv[2]
    baud_rate = 115200

    try:
        # Read the raw machine code
        with open(bin_file, 'rb') as f:
            firmware = f.read()
    except Exception as e:
        print(f"Error reading {bin_file}: {e}")
        sys.exit(1)

    # Calculate padding to ensure word alignment (multiples of 4 bytes)
    padding = (4 - (len(firmware) % 4)) % 4
    firmware += b'\x00' * padding

    print("\n==================================================")
    print("        RISC-V BARE-METAL BOOTLOADER V1.0         ")
    print("==================================================")
    print(f"File: {bin_file} ({len(firmware)} bytes)")
    
    input(f"\n[ACTION REQUIRED] Flip SW[1] UP (Program Mode), then press ENTER...")

    try:
        # Open the serial port
        ser = serial.Serial(com_port, baud_rate, timeout=1)
        
        print("\n[+] Flashing silicon...")
        ser.write(firmware)
        ser.flush()
        
        print("[+] Flash complete!")
        
        input("\n[ACTION REQUIRED] Flip SW[1] DOWN (Run Mode) to start CPU, then press ENTER to open monitor...")
        
        print("\n==================================================")
        print("                 SERIAL MONITOR                   ")
        print("==================================================")
        
        # Infinite loop to listen to the CPU's MMIO outputs
        while True:
            if ser.in_waiting > 0:
                char = ser.read().decode('ascii', errors='ignore')
                print(char, end='', flush=True)
            time.sleep(0.001)

    except serial.SerialException as e:
        print(f"\n[!] Serial Error: Could not open {com_port}. Check Device Manager!")
    except KeyboardInterrupt:
        print("\n\n[+] Exiting Serial Monitor.")
    finally:
        if 'ser' in locals() and ser.is_open:
            ser.close()

if __name__ == "__main__":
    main()