import serial
import time

COM_PORT = "COM11" # Change to correct COM port on your device
BAUD_RATE = 38_400

HEADER_CONST = 0xC  # Set digits per line (1 - 15)

with open("input.txt", "r") as f:
    lines = [line.strip() for line in f.readlines() if line.strip()]

inl = ["1638443288937575332623652774753666225617276523584326435233644435435475136747557213637428364562364222",
"3321623215212542214212421123222426522222433132242242252262222722328142222222123226422221223222155389",
"3652353332235222312654422632323222352336234432232537434232233323339225325363122653543323432221132825",
"2122322222222231134132222222422221217222322212221122226122412221222212122233222242352123232232232322",
"3245355131225321425124122442562435222125236532344452424822541554253226545415432432352232465432354659"]


#lines = [line.strip() for line in inl]
# ^ Uncomment to use above test case (same as in testbench)

num_lines = len(lines)

if num_lines == 0:
    raise ValueError("input.txt contains no valid lines")

# All lines must be same length
line_len_hex = len(lines[0]);
if any(len(line) != line_len_hex for line in lines):
    raise ValueError("All lines in input.txt must have the same hex length")

if line_len_hex > 100:
    raise ValueError("Line length too long (max 100)")

if num_lines > 0xFFF:
    raise ValueError("Too many lines (max 4095)")

# If line length is odd, then pad all with leading 0s (does not change result)
if line_len_hex % 2 != 0:
    print("Odd line length -> padding start")
    for idx, line in enumerate(lines):
        lines[idx] = "0" + line

print(f"Loaded {num_lines} lines from input.txt")

# Header: 0xAAxxyyyz
# xx = line length in bytes (1 byte) (max 100)
# yyy = number of lines (12-bit value)
# z = number of digits from each line

header = bytearray()
header.append(0xAA)
header.append((line_len_hex // 2) & 0xFF)
header.append((num_lines >> 4) & 0xFF)      # upper 8 bits of yyy
header.append(((num_lines & 0xF) << 4) | (HEADER_CONST & 0xF))

print(f"Header bytes: {header.hex()}")

# Encode all lines into bytes
encoded_lines = []

for line in lines:
    # Convert hex -> bytes (MSB first)
    encoded = bytes(int(line[i:i+2], 16) for i in range(0, len(line), 2))
    encoded_lines.append(encoded)

# Join into single payload
payload = header + b"".join(encoded_lines)

#encoded_lines = map(bytes.fromhex, lines)
#payload = header + b"".join(encoded_lines)

with open("payload.bin", "wb") as f:
    f.write(payload)

print(f"Total payload size: {len(payload)} bytes")

# Send over UART
start_time = time.time()

try:
    ser = serial.Serial(
        port=COM_PORT,
        baudrate=BAUD_RATE,
        bytesize=serial.EIGHTBITS,
        parity=serial.PARITY_EVEN,
        stopbits=serial.STOPBITS_ONE,
        timeout=2,
        write_timeout=2,
        inter_byte_timeout=0.1
    )

    print(f"Port opened: {ser.name}")

    ser.reset_input_buffer()
    ser.reset_output_buffer()

    time.sleep(0.01)
    print("Sending header + data...")
    
    ser.write(payload)
    ser.flush()
    
    print("Sent!\n")

    # Expect exactly 8 bytes back (64 bit value)
    response = ser.read(8)

    ser.close()

    end_time = time.time()
    runtime = end_time - start_time

    if len(response) == 8:
        print(f"Received 8 bytes: {response.hex()}")

        value = int.from_bytes(response, byteorder="big")
        print(f"Decimal value: {value}")

        print(f"\nTotal runtime: {runtime:.4f} seconds ({runtime*1000:.2f} ms)")
    else:
        print(f"Expected 8 bytes, received {len(response)}")
        print(f"Hex: {response.hex()}")

except Exception as e:
    print(f"Error: {e}")

