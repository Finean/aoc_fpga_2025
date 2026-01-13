`timescale 1ns / 1ps

module testbench(
    );
    
    parameter CLK_FREQ = 12_000_000;
    parameter CLK_PERIOD = 1_000_000_000 / CLK_FREQ; // ns
    
    
    reg sysclk;
    reg reset_in;
    wire [63:0] calc_area;
    wire uart;
    
    top DUT(
        .sysclk(sysclk),
        .reset(reset_in),
        .uart_rxd_out(uart)
    );

    initial begin
        sysclk = 0;
        reset_in = 1;
        #(CLK_PERIOD * 10);
        reset_in = 0;
        
        forever #(CLK_PERIOD/2) sysclk = ~sysclk;
    end 
    
    int num_cycles = 0;
    
    initial begin
        @(negedge reset_in);
        @(posedge sysclk);
    
        while (!(DUT.state == 3)) begin
            #(CLK_PERIOD);
        end
        
        $display("Finished running in: %0d cycles", DUT.cycles);
        $display("Computed value: %0d", DUT.out_area);
        $display("%0.3f ms", (DUT.cycles * CLK_PERIOD) / 1_000_000.0);
        $display("Info: %0d search-wait cycles (%0.3f ms)", DUT.solv0.debug_wait_cycles, (DUT.solv0.debug_wait_cycles * CLK_PERIOD) / 1_000_000.0 );
        
        $stop;
    end
endmodule
