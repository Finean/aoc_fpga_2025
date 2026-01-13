`timescale 1ns / 1ps

import params::*;

module top(
    input sysclk,
    input reset,
    output uart_rxd_out
    );
    
    reg [31:0] cycles;
    reg [31:0] counter;
    
    reg [3:0] state;
    reg reset_reg;
    wire done;
    wire [63:0] out_area;
    
    reg uart_xmit;
    reg [7:0] uart_data;
    wire uart_ready;
    
    initial begin
        cycles = 0;
        counter = 0;
        state = 0;
        reset_reg = 1;
        uart_xmit = 0;
    end
    
    solver solv0(
        .sysclk(sysclk),
        .reset(reset_reg),
        .done(done),
        .out_area(out_area)
    );
    
    uart_tx uart0(
        .clk(sysclk),
        .data(uart_data),
        .xmit(uart_xmit),
        .tx(uart_rxd_out),
        .ready(uart_ready)
    );
    
    always_ff @(posedge sysclk) begin
        if (reset) begin
            state <= 0;
            counter <= 0;
            reset_reg <= 1;
            uart_xmit <= 0;
            cycles <= 0;
        end
    
        case(state)
            0: begin
                reset_reg <= 1;
                counter <= counter + 1;
                if (counter > (MILLIS * 1)) begin
                    reset_reg <= 0;
                    cycles <= 0;
                    counter <= 0;
                    state <= 1;
                end
            end
            1: begin
                cycles <= cycles + 1;
                if (done) begin
                    state <= 2;
                end
            end
            2: begin
                counter <= counter + 1;
                if (counter > MILLIS * 1) begin
                    uart_xmit <= 0;
                    state <= 3;
                    uart_data <= (out_area[60 +: 4] < 10)
                       ? ("0" + out_area[60 +: 4])
                       : ("A" + (out_area[60 +: 4] - 10));
                    counter <= 0;
                end
            end
            3: begin
                if (counter == 16) begin // Done
                    state <= 4;
                end else if (uart_xmit) begin
                    uart_xmit <= 0;
                    uart_data <= (out_area[60 - 4 * counter +: 4] < 10)
                       ? ("0" + out_area[60 - 4 * counter +: 4])
                       : ("A" + (out_area[60 - 4 * counter +: 4] - 10));
                end else if (uart_ready) begin
                    counter <= counter + 1;
                    uart_xmit <= 1;
                end
            end
        endcase
    end
endmodule
