`timescale 1ns / 1ps

module day3(
    input sysclk,
    input uart_txd_in,
    output uart_rxd_out
    );
    
    parameter INIT = 10'b0000000001;
    parameter HEAD = 10'b0000000010;
    parameter WAIT = 10'b0000000100;
    parameter RECV = 10'b0000001000;
    parameter CALC = 10'b0000010000;
    parameter NEXT = 10'b0000100000;
    parameter SEND = 10'b0001000000;
    parameter CLHI = 10'b0010000000;
    parameter CLLO = 10'b0100000000;
    parameter RSET = 10'b1000000000;
    
    reg [9:0] state;
    
    reg [399:0] data; // Store current line
    reg [63:0] sum; // Stores the sum (result)
    reg [63:0] sum_buf; // Stores value from current line
    reg [31:0] header_data; // Stores header data
    reg [11:0] cur_line;
    reg [7:0] counter;
    reg [7:0] adr;
    reg [7:0] prev_adr;
   
    // UART regs + wires
    reg [7:0] tx_out;
    reg clk_out;
    reg rx_rst;
    
    wire tx_ready;
    wire [7:0] in_data;
    wire in_par;
    wire in_recd;
   
    wire [3:0] cur_max;
    wire [7:0] cur_adr;
    wire [63:0] bin_val;
    
    wire [3:0] n_digits = header_data[0 +: 4];
    wire [6:0] c_digit = counter >> 1;
    wire [7:0] right_mask = n_digits - 1 - c_digit;
    
    //Example line
    initial begin
        data = 0;
        state = INIT;
        adr = 0;
        header_data = 0;
        cur_line = 12'h01F;
        counter = 0;
        sum = 0;
        sum_buf = 0;
        prev_adr = 8'hFF;
        
        tx_out = 0;
        clk_out = 0;
        rx_rst = 0;
    end
    
    // Load data from register
    find_max max0 ( 
        .data(data),
        .prev_adr(prev_adr),
        .mask(right_mask),
        .max_val(cur_max),
        .max_adr(cur_adr)
    );
    
    ua_tx tx0 (
        .clk(sysclk),
        .data(tx_out),
        .xmit(clk_out),
        .tx(uart_rxd_out),
        .ready(tx_ready)
    );
    
    ua_rx rx0 (
        .clk(sysclk),
        .reset(rx_rst),
        .rx_in(uart_txd_in),
        .value(in_data),
        .par_ok(in_par),
        .recd(in_recd)
    );
    
    // Only needed to convert sum_buf to its hex value
    dec64_to_bin dtb0 ( 
        .dec_digits(sum_buf),
        .value(bin_val)
    );
    
    //Module to find largest digit in 99 digit range - output both digit and address from array
    always @(posedge sysclk) begin
        case (state)
            INIT: begin // Initialise
                if (cur_line < 2) begin
                    cur_line <= 0;
                    data <= 0;
                    sum <= 0;
                    sum_buf <= 0;
                    counter <= 0;
                    state <= HEAD;
                end else
                    cur_line <= cur_line - 1;
            end
            HEAD: begin // Listen for 4 byte header 0xAAxxyyyz -> xx is length of line (max 100), yyy is number of lines (max 4095), z is number of digits to find per line (max 15)
                if (in_recd & ~rx_rst) begin
                    header_data <= {header_data[0 +: 24], in_data};
                    counter <= counter + 1;
                    rx_rst <= 1;
                    if (counter == 3)
                        state <= WAIT;
                end else begin
                    rx_rst <= 0;
                end
            end
            WAIT: begin
                cur_line <= header_data[4 +: 12];
                prev_adr <= 8'hFF;
                adr <= 0;
                counter <= 0;
                state <= RECV;
            end
            RECV: begin //Listen for x values (x / 2 packets) -> only supports even length (pad odd length with 0 at start)
                if (cur_line == 0) begin
                    state <= SEND;
                    counter <= 0;
                end else if (in_recd & ~rx_rst) begin
                    data <= {data[391:0], in_data};
                    counter <= counter + 1;
                    rx_rst <= 1;
                    if (counter == header_data[16 +: 8] - 1) begin
                        state   <= CALC;
                        counter <= 0;
                    end
                end else begin
                    rx_rst <= 0;
                end
            end 
            CALC: begin // Find digits
                case (counter[0])
                    1'b0: begin // Load value in max module
                        // Adr (0 is most significant bit on data)
                        prev_adr <= adr;
                        counter <= counter + 1;
                    end
                    default: begin // Read output from max module
                        sum_buf[4 * (n_digits - 1 - c_digit) +: 4] <= cur_max;
                        adr <= cur_adr;
                        counter <= counter + 1;
                        if (c_digit >= (n_digits - 1)) begin // All digits done
                            cur_line <= cur_line - 1;
                            counter <= 0;
                            state <= NEXT;
                        end
                    end
                endcase
            end
            NEXT: begin
                sum <= sum + bin_val;
                data <= 0;
                prev_adr <= 8'hFF;
                adr <= 0;
                state <= RECV;
            end
            SEND: begin
                if (counter == 8) begin
                    counter <= 0;
                    state <= RSET;
                end else if (tx_ready) begin
                    tx_out <= sum[56 - 8*counter +: 8];
                    counter <= counter + 1;
                    state <= CLHI;
                end
            end
            CLHI: begin
                clk_out <= 1;
                state <= CLLO;
            end
            CLLO: begin
                clk_out <= 0;
                state <= SEND;
            end
            RSET: begin
                if (counter >= 100) begin
                    // Only reset what's needed for next iteration
                    sum <= 0;
                    counter <= 0;
                    rx_rst <= 0;
                    prev_adr <= 8'hFF;
                    state <= HEAD;
                end else
                    counter <= counter + 1;
            end
            default: ;
        endcase
    end
endmodule

module find_max(
    input [399:0] data,
    input [7:0] prev_adr,
    input [7:0] mask,
    output [3:0] max_val,
    output [7:0] max_adr
    );
    
    // Biased towards earlier (more significant) digits
    // Returns max_adr from data - 0 = MSB
    reg [3:0] max;
    reg [7:0] adr;
    reg [3:0] current;
    reg done;  // Flag to stop checking after finding 9
    integer i;
    
    always @(*) begin
        max = 4'h0;
        adr = 0;
        done = 0;
        
        for (i = 0; i < 100; i = i + 1) begin
            if (!done && (i > prev_adr) && (i <= 99 - mask)) begin
                current = data[396 - (i * 4) +: 4];
                if (current > max) begin
                    max = current;
                    adr = i;
                    if (max == 4'h9) begin
                        done = 1;  // Set flag instead of breaking
                    end
                end
            end
        end
    end
    
    assign max_adr = adr;
    assign max_val = max;
    
endmodule

module dec64_to_bin #(
    parameter DIGITS = 16
)(
    input  wire [63:0] dec_digits,   // 16 × 4-bit digits
    output reg  [63:0] value
);
    integer i;
    reg [3:0] d;

    always @(*) begin
        value = 0;
        for (i = 0; i < DIGITS; i = i + 1) begin
            d = dec_digits[(DIGITS-1-i)*4 +: 4];  // MS digit first
            // value * 10 = value * 8 + value * 2 = (value << 3) + (value << 1)
            value = (value << 3) + (value << 1) + d;
        end
    end
endmodule

module ua_tx #(
    parameter CLK_FREQ  = 12_000_000,
    parameter BAUD_RATE = 38_400
)(
    input        clk,
    input  [7:0] data,
    input        xmit,
    output reg   tx,
    output       ready
);

    localparam integer CYCLES_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam integer BIT_PERIOD     = CYCLES_PER_BIT - 1;

    reg [10:0] shifter;   // 8 data + parity + 2 x stop
    reg [3:0]  bit_index; // 0..10
    reg [15:0] counter;
    reg        busy;

    assign ready = ~busy;

    initial begin
        tx        = 1;
        busy      = 0;
        counter   = 0;
        bit_index = 0;
        shifter   = 0;
    end

    always @(posedge clk) begin
        if (!busy) begin
            if (xmit) begin
                shifter   <= {2'b11, (^data), data};
                busy      <= 1;
                bit_index <= 0;
                counter   <= 0;
                tx        <= 0;  // start bit
            end
        end else begin
            if (counter == BIT_PERIOD) begin
                counter <= 0;

                // shift out next bit
                tx <= shifter[0];
                shifter <= {1'b1, shifter[10:1]};
                bit_index <= bit_index + 1;

                // stop after shifting bit 10 (2nd stop bit)
                if (bit_index == 10) begin
                    busy <= 0;
                    tx   <= 1; // idle
                end
            end else begin
                counter <= counter + 1;
            end
        end
    end
endmodule

module ua_rx #(
    parameter CLK_FREQ = 12_000_000,  // Clock frequency in Hz (default 12 MHz)
    parameter BAUD_RATE = 38_400
    )
    (
    input clk,
    input reset,
    input rx_in,
    output reg [7:0] value,
    output reg par_ok,
    output reg recd
    );
    
    // Calculate cycles per bit at compile time
    localparam integer CYCLES_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam integer SAMPLE_POINT = CYCLES_PER_BIT / 2;  // Sample in middle of bit
    
    reg rx1, rx2;
    always @(posedge clk) begin
        rx1 <= rx_in;
        rx2 <= rx1;
    end
    
    reg [15:0] counter;
    reg [3:0] cur_bit;  // 0=start, 1-8=data, 9=parity, 10=stop
    reg [7:0] data;
    reg busy;
    
    initial begin 
        busy = 0;
        data = 0;
        par_ok = 0;
        cur_bit = 0;
        counter = 0;
        rx1 = 1;
        rx2 = 1;
        recd = 0;
        value = 0;
    end
    
    always @(posedge clk) begin
        if (reset) begin
            busy <= 0;
            counter <= 0;
            cur_bit <= 0;
            data <= 0;
            par_ok <= 0;
            recd <= 0;
        end else begin
            recd <= 0;  // Clear by default (single-cycle pulse)
            
            if (!busy) begin
                if (~rx2) begin  // Detect start bit
                    busy <= 1;
                    counter <= 0;
                    cur_bit <= 0;
                end
            end else begin
                if (counter == SAMPLE_POINT) begin
                    counter <= counter + 1;
                    
                    case (cur_bit)
                        0: begin
                            if (rx2 != 0) busy <= 0;  // Invalid start
                        end
                        1, 2, 3, 4, 5, 6, 7, 8: begin
                            data[cur_bit - 1] <= rx2;
                        end
                        9: begin
                            // Fixed parity check for even parity
                            par_ok <= (^{data, rx2}) == 1'b0;
                        end
                        10: begin
                            if (rx2 == 1) begin
                                value <= data;
                                recd <= 1;  // Single-cycle pulse
                            end
                        end
                    endcase
                    
                end else if (counter == CYCLES_PER_BIT - 1) begin
                    counter <= 0;
                    if (cur_bit == 10) begin
                        busy <= 0;
                        cur_bit <= 0;
                    end else begin
                        cur_bit <= cur_bit + 1;
                    end
                end else begin
                    counter <= counter + 1;
                end
            end
        end
    end
endmodule