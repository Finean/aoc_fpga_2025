`timescale 1ns / 1ps

module testbench;
    
    parameter CLK_FREQ = 12_000_000;
    parameter BAUD_RATE = 38_400;
    
    parameter CLK_PERIOD = 1_000_000_000 / CLK_FREQ; // ns
    parameter CYCLES_PER_BIT = CLK_FREQ / BAUD_RATE;
    parameter SAMPLE_POINT = CYCLES_PER_BIT / 2;
    
    reg sysclk;
    reg uart_txd_in;
    wire uart_rxd_out;    
    
    day3 u0 (
        .sysclk(sysclk),
        .uart_txd_in(uart_txd_in),
        .uart_rxd_out(uart_rxd_out)
    );
   
    initial begin
        sysclk = 0;
        forever #(CLK_PERIOD/2) sysclk = ~sysclk;
    end
    
    reg [7:0] test_data [0:53];  // 54 bytes (header + 100 digits)
    integer i;
    
    function parity;
        input [7:0] data;
        integer k;
        begin
            parity = ^ data;
        end
    endfunction
    
    task uart_send_byte;
        input [7:0] data;
        integer j;
        reg par;
        begin
            par = ^ data;
            
            // Start bit
            uart_txd_in = 0;
            #(CLK_PERIOD * CYCLES_PER_BIT);  // UART bit period

            for (j = 0; j < 8; j = j + 1) begin
                uart_txd_in = data[j];
                #(CLK_PERIOD * CYCLES_PER_BIT);
            end
            
            // Even parity bit
            uart_txd_in = par;
            #(CLK_PERIOD * CYCLES_PER_BIT);
            
            // Stop bit
            uart_txd_in = 1;
            #(CLK_PERIOD * CYCLES_PER_BIT);
        end
    endtask
    
    task uart_receive_byte;
        output [7:0] data;
        integer j;
        reg par_received, par_calculated;
        begin
            // Wait for start bit (line goes low)
            wait (uart_rxd_out == 0);
    
            // Move to middle of start bit
            #(CLK_PERIOD * SAMPLE_POINT);
    
            if (uart_rxd_out != 0)
                $display("WARNING: False start bit detected at time %0t", $time);
    
            // Move to middle of first data bit
            #(CLK_PERIOD * CYCLES_PER_BIT);
    
            // Read 8 data bits
            for (j = 0; j < 8; j = j + 1) begin
                data[j] = uart_rxd_out;
                #(CLK_PERIOD * CYCLES_PER_BIT);
            end
    
            par_received  = uart_rxd_out;
            par_calculated = parity(data);
    
            if (par_received != par_calculated) begin
                $display("WARNING: Parity error - Received=%b, Calculated=%b, data=0x%02h, time=%0t",
                         par_received, par_calculated, data, $time);
            end
    
            // Move to middle of stop bit
            #(CLK_PERIOD * CYCLES_PER_BIT);
            if (uart_rxd_out != 1) begin
                $display("WARNING: Stop bit error at time %0t, uart_rxd_out=%b", $time, uart_rxd_out);
            end
    
            // Finish stop bit
            #(CLK_PERIOD * SAMPLE_POINT);
        end
    endtask

    
    // Function to convert ASCII/UTF-8 character to decimal digit
    function [3:0] ascii_to_digit;
        input [7:0] ascii_char;
        begin
            if (ascii_char >= 8'h30 && ascii_char <= 8'h39)
                ascii_to_digit = ascii_char - 8'h30;  // '0' to '9'
            else
                ascii_to_digit = 4'hF;  // Invalid
        end
    endfunction
    
    // Background task to continuously listen for UART output
    reg [7:0] received_chars [0:23];  // Store 24 UTF-8 characters
    integer char_count;
    integer k;
    reg [7:0] result_value;
    reg result_complete;

    initial begin
        char_count = 0;
        result_complete = 0;
    
        // Wait for DUT to stabilise
        #(CLK_PERIOD * 100);
    
        forever begin
            uart_receive_byte(received_chars[char_count]);
        
            // Print each received byte as hex only
            $display("Time %0t: Received byte %0d = 0x%02h",
                     $time, char_count, received_chars[char_count]);
        
            // Stop once 8 bytes have been received
            if (char_count == 7) begin
                $write("Received 64-bit hex result: ");
                result_complete = 1;
        
                // Print all 8 bytes as hex (no ASCII)
                for (k = 0; k < 8; k = k + 1)
                    $write("%02h", received_chars[k]);
        
                $display("");
        
                #(CLK_PERIOD * 1000);
                $finish;
            end
            char_count = char_count + 1;
        end
    end
    
    task load_line;
        input [399:0] line_bits;
        integer idx;
        begin
            for (idx = 0; idx < 50; idx = idx + 1)
                test_data[idx] = line_bits[399 - idx*8 -: 8];
        end
    endtask
    
    task test_case;
        reg [399:0] lines [0:4];
    
        begin
        
            //Result for 12 digits is 4451415640417 = 0x0000040C6D0C4961
            lines[0] = 400'h1638443288937575332623652774753666225617276523584326435233644435435475136747557213637428364562364222;
            lines[1] = 400'h3321623215212542214212421123222426522222433132242242252262222722328142222222123226422221223222155389;
            lines[2] = 400'h3652353332235222312654422632323222352336234432232537434232233323339225325363122653543323432221132825;
            lines[3] = 400'h2122322222222231134132222222422221217222322212221122226122412221222212122233222242352123232232232322;
            lines[4] = 400'h3245355131225321425124122442562435222125236532344452424822541554253226545415432432352232465432354659;
        
            // Send header
            uart_send_byte(8'hAA);
            #(CLK_PERIOD * 20);
            uart_send_byte(8'h32); // line length in bytes
            #(CLK_PERIOD * 20);   
            uart_send_byte(8'h00); // yyy high  
            #(CLK_PERIOD * 20);
            uart_send_byte(8'h5C); // yyy low nibble + z = number of digits
            #(CLK_PERIOD * 20);  
            $display("Test Case");
            $display("Sending data via UART...");
            // Send all 5 lines
            for (i = 0; i < 5; i = i + 1) begin
                load_line(lines[i]);
                for (k = 0; k < 50; k = k + 1) begin
                    uart_send_byte(test_data[k]);
                    #(CLK_PERIOD * 20);
                end
            end
        end
    endtask
    
    initial begin
        $display("Starting Day 3 Testbench");
        $display("Expecting output as 16 hex digits");
        $dumpfile("day3_tb.vcd");
        $dumpvars(0, testbench);
        
        // Initialize
        uart_txd_in = 1;  // Idle high
        
        // Wait for initialization (state 0x00)
        #(CLK_PERIOD * 5000);
        
        // Run the specific test case
        test_case();
        
        // The receiver task will handle completion and $finish
    end
    
    // Watch for timeout
    initial begin
        #(CLK_PERIOD * 2000000);
        $display("ERROR: Testbench timeout");
        $finish;
    end
    
    // Monitor data reception
    always @(posedge u0.in_recd) begin
        $display("Time %0t: received input byte 0x%h (counter = %0d)", $time, u0.in_data, u0.counter);
    end
    
    // Monitor transmission starts
    always @(posedge u0.clk_out) begin
        $display("Time %0t: Transmit: tx_out=0x%h", $time, u0.tx_out);
    end

endmodule