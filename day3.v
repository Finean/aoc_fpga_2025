`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05.01.2026 13:23:46
// Design Name: 
// Module Name: day3
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module day3_part1(
    input sysclk,
    input uart_txd_in,
    output uart_rxd_out
    );
    
    // Using 2 digits for part 2
    reg [399:0] data;
    reg [395:0] cur_data;
    reg [7:0] out;
    reg [7:0] state;
    reg [7:0] counter;
    reg [7:0] adr;
    reg busy;
    
    reg [7:0] tx_out;
    reg clk_out;
    reg rx_rst;
    
    wire tx_ready;
    wire [7:0] in_data;
    wire in_par;
    wire in_recd;
    
    
    
    wire [3:0] cur_max;
    wire [7:0] cur_adr;
    
    
    //Example line
    initial begin
        data = 0;
        cur_data = 0;
        state = 8'h00;
        counter = 0;
        adr = 0;
        
        tx_out = 0;
        clk_out = 0;
        rx_rst = 0;
        out = 0;
    end
    
    // Load data from register
    find_max max0 ( 
        .data(cur_data),
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
    
    //Module to find largest digit in 99 digit range - output both digit and address from array
    always @(posedge sysclk) begin
        case (state)
            8'h00: begin
                if (counter > 250) begin
                    counter <= 0;
                    state <= 1;
                end else
                    counter <= counter + 1;
            end
            8'h01: begin //Listen for 100 values (50 packets)
                if (in_recd & ~rx_rst) begin
                    data <= {in_data, data[399:8]};
                    counter <= counter + 1;
                    rx_rst <= 1;
                    if (counter >= 49) begin  // After this byte, we'll have 50
                        state <= state + 1;
                        counter <= 0;
                    end
                end else begin
                    rx_rst <= 0;
                end
            end 
            8'h02: begin // Find first digit
                cur_data <= data[399:4];  // Search first 99 digits
                state <= state + 1;
            end
            8'h03: begin // Store first result
                out[4 +: 4] <= cur_max;
                tx_out <= 8'h30 + {4'h0, cur_max};
                adr <= cur_adr;
                state <= state + 1;
            end
            8'h04: begin // Find second digit
                // adr is the digit index (0=most significant)
                // We want to search only digits AFTER (less significant than) adr
                // Zero out bits [395:392-adr*4] to exclude digit 0 through adr
                cur_data <= (data[395:0] << (adr * 4 + 4)) >> (adr * 4 + 4);
                state <= state + 1;
            end
            8'h05: begin // Store second result
                out[0 +: 4] <= cur_max;   // Store second max digit (ones place)
                state <= state + 1;
            end
            8'h06: begin // Pulse xmit high for first digit
                clk_out <= 1;
                state <= state + 1;
            end
            8'h07: begin // Clear xmit pulse
                clk_out <= 0;
                state <= state + 1;
            end
            8'h08: begin // Wait for first transmission to complete
                if (tx_ready) begin
                    state <= state + 1;
                end
            end
            8'h09: begin // Prepare second digit for transmission
                tx_out <= 8'h30 + {4'h0, out[0 +: 4]};
                state <= state + 1;
            end
            8'h0A: begin // Pulse xmit high for second digit
                clk_out <= 1;
                state <= state + 1;
            end
            8'h0B: begin // Clear xmit pulse
                clk_out <= 0;
                state <= state + 1;
            end
            8'h0C: begin // Wait for second transmission to complete
                if (tx_ready) begin
                    rx_rst <= 0;
                    state <= 1;
                end
            end
            default: ;
        endcase
    end
endmodule




module find_max(
    input [395:0] data,
    output [3:0] max_val,
    output [7:0] max_adr
    );
    
    // Biased towards earlier (more significant) digits
    // Returns max_adr from data

    reg [3:0] max;
    reg [7:0] adr;
    reg [3:0] current;
    integer i;
    
    always @(*) begin
        max = 4'h0;
        adr = 8'h0;
        
        for (i = 0; i < 99; i = i + 1) begin
            current = data[392 - (i * 4) +: 4];
            if (current > max) begin
                max = current;
                adr = i;
            end
        end
    end

    assign max_adr = adr;
    assign max_val = max;
    
endmodule

module ua_tx #(
    parameter CLK_FREQ = 12_000_000,  // Clock frequency in Hz (default 12 MHz)
    parameter BAUD_RATE = 9600        // Baud rate (default 9600)
) (
    input clk,
    input [7:0] data,
    input xmit,
    output reg tx,
    output ready
    );
    
    // Calculate cycles per bit at compile time
    localparam CYCLES_PER_BIT = CLK_FREQ / BAUD_RATE;
    
    reg [3:0] cur_dig;
    reg [15:0] counter;
    reg [10:0] xmit_value;
    reg busy;
    
    wire parity;
    wire [10:0] out;
    
    assign parity = ^ data; // Even parity bit
    assign out = {1'b1, parity, data, 1'b0};
    
    initial begin 
        tx = 1;
        busy = 0;
        counter = 0;
        cur_dig = 0;
        xmit_value = 0;
    end
    
    always @(posedge clk) begin
    
        // On xmit high initialise packet
        if (xmit && !busy) begin
            busy <= 1;
            counter <= 0;
            cur_dig <= 0;
            xmit_value <= out;
        end
        else if (busy) begin
            // Wait CYCLES_PER_BIT cycles for each bit
            // Load next value on counter = 0
            if (counter == 0) begin
                tx <= xmit_value[cur_dig];
                counter <= counter + 1;
            end
            else if (counter >= (CYCLES_PER_BIT - 1)) begin
                counter <= 0;
                if (cur_dig == 10) begin
                    tx <= 1;
                    busy <= 0;
                end
                else
                    cur_dig <= cur_dig + 1;
            end
            else
                counter <= counter + 1;
        end
    end
    
    assign ready = ~busy;
endmodule

module ua_rx #(
    parameter CLK_FREQ = 12_000_000,  // Clock frequency in Hz (default 12 MHz)
    parameter BAUD_RATE = 9600        // Baud rate (default 9600)
) (
    input clk,
    input reset,
    input rx_in,
    output reg [7:0] value,
    output reg par_ok,
    output reg recd
    );
    
    // Calculate cycles per bit at compile time
    localparam CYCLES_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam SAMPLE_POINT = CYCLES_PER_BIT / 2;  // Sample in middle of bit
    
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
            // Start transmission on falling edge (start bit)
            if (!busy) begin
                recd <= 0;
                if (~rx2) begin  // Detect start bit
                    busy <= 1;
                    counter <= 0;
                    cur_bit <= 0;
                end
            end else begin
                case (counter)
                    SAMPLE_POINT: begin // Sample in middle of bit
                        counter <= counter + 1;
                        
                        case (cur_bit)
                            0: begin
                                // Start bit - should be 0, just verify
                                if (rx2 != 0) begin
                                    // Invalid start bit, reset
                                    busy <= 0;
                                end
                            end
                            1, 2, 3, 4, 5, 6, 7, 8: begin
                                // Data bits (LSB first)
                                data[cur_bit - 1] <= rx2;
                            end
                            9: begin
                                // Parity bit (even parity)
                                par_ok <= ((^data) == rx2);  // True if parity matches
                            end
                            10: begin
                                // Stop bit - should be 1
                                if (rx2 == 1) begin
                                    value <= data;
                                    recd <= 1;
                                end
                                // Will reset on next cycle
                            end
                        endcase
                    end
                    
                    (CYCLES_PER_BIT - 1): begin // End of bit period
                        counter <= 0;
                        
                        if (cur_bit == 10) begin
                            // Finished receiving complete frame
                            busy <= 0;
                            cur_bit <= 0;
                        end else begin
                            cur_bit <= cur_bit + 1;
                        end
                    end
                    
                    default: counter <= counter + 1;
                endcase
            end
        end
    end
endmodule