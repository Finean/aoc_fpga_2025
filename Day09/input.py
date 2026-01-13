def to_20bit_bin(n: int) -> str:
    # P to length 20
    return f"{n & 0xFFFFF:020b}"

x_lines = []
y_lines = []

with open("input.txt") as f:
    for line in f:
        a_str, b_str = line.strip().split(",")
        x = int(a_str)  # x coordinate
        y = int(b_str)  # y coordinate
        
        bin_x = to_20bit_bin(x)
        bin_y = to_20bit_bin(y)
        
        x_lines.append(bin_x)
        y_lines.append(bin_y)

with open("output_x.bin", "w") as f:
    print(f"Loaded {len(x_lines)} lines from input.txt")
    for line in x_lines:
        f.write(line + "\n")
    f.write(x_lines[0] + "\n")  # Repeat first point

with open("output_y.bin", "w") as f:
    for line in y_lines:
        f.write(line + "\n")
    f.write(y_lines[0] + "\n")  # Repeat first point

print("Input written to output_x.bin and output_y.bin")
