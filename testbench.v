`timescale 1ns / 1ps

module testbench;
    
    parameter CLK_PERIOD = 10;
    
    reg sysclk;
    reg uart_txd_in;
    wire uart_rxd_out;    
    
    day3_part1 u0 (
        .sysclk(sysclk),
        .uart_txd_in(uart_txd_in),
        .uart_rxd_out(uart_rxd_out)
    );
   
    initial begin
        sysclk = 0;
        forever #(CLK_PERIOD/2) sysclk = ~sysclk;
    end
    
    reg [7:0] test_data [0:49];  // 50 bytes (100 digits)
    integer i;
    
    function parity;
        input [7:0] data;
        integer k;
        begin
            parity = 0;
            for (k = 0; k < 8; k = k + 1)
                parity = parity ^ data[k];
        end
    endfunction
    
    task uart_send_byte;
        input [7:0] data;
        integer j;
        reg par;
        begin
            par = parity(data);
            
            // Start bit
            uart_txd_in = 0;
            #(CLK_PERIOD * 1250);  // UART bit period

            for (j = 0; j < 8; j = j + 1) begin
                uart_txd_in = data[j];
                #(CLK_PERIOD * 1250);
            end
            
            // Even parity bit
            uart_txd_in = par;
            #(CLK_PERIOD * 1250);
            
            // Stop bit
            uart_txd_in = 1;
            #(CLK_PERIOD * 1250);
        end
    endtask
    
    task uart_receive_byte;
        output [7:0] data;
        integer j;
        reg par_received, par_calculated;
        begin
            // Wait for start bit
            wait(uart_rxd_out == 0);
            #(CLK_PERIOD * 625);  // Half bit period to sample in middle
            
            // Read data bits
            for (j = 0; j < 8; j = j + 1) begin
                #(CLK_PERIOD * 1250);
                data[j] = uart_rxd_out;
            end
            
            // Read parity bit
            #(CLK_PERIOD * 1250);
            par_received = uart_rxd_out;
            par_calculated = parity(data);
            
            if (par_received != par_calculated) begin
                $display("WARNING: Parity error! Received=%b, Calculated=%b", 
                         par_received, par_calculated);
            end
            
            // Wait for stop bit
            #(CLK_PERIOD * 1250);
            if (uart_rxd_out != 1) begin
                $display("WARNING: Stop bit error");
            end
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
    reg [7:0] received_chars [0:1];  // Store two UTF-8 characters
    integer char_count;
    reg [7:0] result_value;
    reg result_complete;
    
    initial begin
        char_count = 0;
        result_complete = 0;
        forever begin
            uart_receive_byte(received_chars[char_count]);
            $display("Time %0t: Received UTF-8 character %0d: 0x%h ('%c')", 
                     $time, char_count, received_chars[char_count], received_chars[char_count]);
            
            char_count = char_count + 1;
            
            // After receiving both characters, decode the result
            if (char_count == 2) begin
                result_value = ascii_to_digit(received_chars[0]) * 10 + 
                               ascii_to_digit(received_chars[1]);
                
                $display("RESULT RECEIVED:");
                $display("  Tens digit character: '%c' (0x%h) = %0d", 
                         received_chars[0], received_chars[0], ascii_to_digit(received_chars[0]));
                $display("  Ones digit character: '%c' (0x%h) = %0d", 
                         received_chars[1], received_chars[1], ascii_to_digit(received_chars[1]));
                $display("  Decoded decimal value: %0d", result_value);
                
                result_complete = 1;
                
                // Reset for potential additional outputs
                char_count = 0;
            end
        end
    end
    
    task load_hex_string;
        input [399:0] hex_string;  // 100 hex digits * 4 bits = 400 bits
        integer idx;
        begin
            $display("Loading hex string into test_data array...");
            for (idx = 0; idx < 50; idx = idx + 1) begin
                // Each byte contains 2 hex digits (8 bits)
                // hex_string is stored with MSB first
                // Extract 8 bits at a time from the string
                test_data[idx] = hex_string[399 - (idx * 8) -: 8];
                $display("  test_data[%0d] = 0x%h", idx, test_data[idx]);
            end
        end
    endtask
    
    task test_case;
        reg [399:0] input_string;
        begin
            // Enter your 100-digit hex string here as a hex literal
            // Example should output 98 (UTF-8: '9' = 0x39, '8' = 0x38)
            input_string = 400'h1638443288937575332623652774753666225617276523584326435233644435435475136747557213637428364562364222;
            
            $display("Test Case");
            $display("Input: %h", input_string);
            
            // Load the hex string into test_data array
            load_hex_string(input_string);
            
            // Send all 50 bytes
            $display("Sending data via UART...");
            for (i = 0; i < 50; i = i + 1) begin
                $display("Time %0t: Sending byte %0d: 0x%h", $time, i, test_data[i]);
                uart_send_byte(test_data[i]);
                #(CLK_PERIOD * 100);  // Small gap between bytes
            end
            
            $display("All data sent, waiting for UTF-8 result...");
        end
    endtask
    
    initial begin
        $display("Starting Day 3 Part 1 Testbench");
        $display("Expecting output as two UTF-8 characters (ASCII digits)");
        $dumpfile("day3_tb.vcd");
        $dumpvars(0, testbench);
        
        // Initialize
        uart_txd_in = 1;  // Idle high
        
        // Wait for initialization (state 0x00)
        #(CLK_PERIOD * 5000);
        
        // Run the specific test case
        test_case();
        
        // Wait for both characters to be received and decoded
        $display("Waiting for result to be received...");
        wait(result_complete == 1);
        
        // Allow a bit more time to see final state
        #(CLK_PERIOD * 10000);
        
        $display("Test complete");
        $finish;
    end
    
    // Watch for timeout
    initial begin
        #(CLK_PERIOD * 2000000);
        $display("ERROR: Testbench timeout");
        $finish;
    end
    
    // Monitor state changes
    always @(u0.state) begin
        $display("Time %0t: State changed to 0x%h", $time, u0.state);
    end
    
    // Monitor data reception
    always @(posedge u0.in_recd) begin
        $display("Time %0t: received byte 0x%h (counter = %0d)", $time, u0.in_data, u0.counter);
    end
    
    // Monitor internal data register after all bytes received
    always @(u0.counter) begin
        if (u0.state == 8'h01 && u0.counter == 50) begin
            $display("Time %0t: All 50 bytes received. Internal data register:", $time);
            $display("  data[399:0] = 0x%h", u0.data);
        end
    end

endmodule
