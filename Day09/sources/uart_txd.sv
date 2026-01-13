`timescale 1ns / 1ps

import params::*;

module uart_tx(
        input        clk,
        input  [7:0] data,
        input        xmit,
        output reg   tx,
        output       ready
    );

    localparam integer CYCLES_PER_BIT = CLK_FREQ / BAUD_RATE;

    reg [10:0] shifter;   // 8 data, parity (even), 2 x stop
    reg [3:0]  cur_bit; // 0..10
    reg [15:0] counter;
    reg        busy;

    assign ready = ~busy;

    initial begin
        tx        = 1;
        busy      = 0;
        counter   = 0;
        cur_bit = 0;
        shifter   = 0;
    end

    always @(posedge clk) begin
        if (!busy) begin
            if (xmit) begin
                shifter   <= {2'b11, (^data), data}; // Latch data into shifter
                busy      <= 1;
                cur_bit <= 0;
                counter   <= 0;
                tx        <= 0;  // Set tx low for start bit
            end
        end else begin
            if (counter == (CYCLES_PER_BIT - 1)) begin
                counter <= 0;

                // Shift out next bit
                tx <= shifter[0];
                shifter <= {1'b1, shifter[10:1]};
                cur_bit <= cur_bit + 1;

                // Stop after shifting bit 10 (2nd stop bit)
                if (cur_bit == 11) begin
                    busy <= 0;
                    tx   <= 1; // idle
                end
            end else begin
                counter <= counter + 1;
            end
        end
    end
endmodule
