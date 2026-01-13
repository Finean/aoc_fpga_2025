`timescale 1ns / 1ps

import params::*;

module solver(
    input sysclk,
    input reset,
    output done,
    output reg [63:0] out_area
    );
    
    // FSM variables
    localparam RST = 4'h0;
    localparam INIT = 4'h1;
    localparam READ = 4'h2;
    localparam READ_DELAY = 4'h3;
    localparam COMPUTE = 4'h4;
    localparam DONE = 4'h5;
    
    // Split block ram for max port width of 32
    (* ram_style = "block" *) reg [COORD_SIZE - 1:0] vx_data_y [0:NUM_PTS - 1]; 
    (* ram_style = "block" *) reg [COORD_SIZE - 1:0] vx_data_x [0:NUM_PTS - 1];
    
    reg [KEY_SIZE - 1:0] vx_addr_cur;
    reg [KEY_SIZE - 1:0] vx_addr_alt;
    reg [1:0][COORD_SIZE - 1:0] vx_cur;
    reg [1:0][COORD_SIZE - 1:0] vx_alt;
    reg [1:0][COORD_SIZE - 1:0] vx_dual;
    reg [1:0][COORD_SIZE - 1:0] vx_first;
    
    // 6 blocks
    (* ram_style = "block" *) reg [COORD_SIZE - 1:0] horiz_edges_y [0: NUM_PTS - 1]; 
    (* ram_style = "block" *) reg [COORD_SIZE - 1:0] horiz_edges_xa [0: NUM_PTS - 1];
    (* ram_style = "block" *) reg [COORD_SIZE - 1:0] horiz_edges_xb [0: NUM_PTS - 1];
    
    (* ram_style = "block" *) reg [COORD_SIZE - 1:0] vertic_edges_x [0: NUM_PTS - 1]; 
    (* ram_style = "block" *) reg [COORD_SIZE - 1:0] vertic_edges_ya [0: NUM_PTS - 1];
    (* ram_style = "block" *) reg [COORD_SIZE - 1:0] vertic_edges_yb [0: NUM_PTS - 1];    
    
    // BRAM address registers
    reg [KEY_SIZE - 1:0] he_addr_a;
    reg [KEY_SIZE - 1:0] he_addr_b;
    reg [KEY_SIZE - 1:0] ve_addr_a;
    reg [KEY_SIZE - 1:0] ve_addr_b;
    
    // Data information
    reg [KEY_SIZE - 1:0] h_edges;
    reg [KEY_SIZE - 1:0] v_edges;
    reg [KEY_SIZE - 1:0] occupied; // Total number of points
    
    // State info
    reg [3:0] state;
    reg [15:0] counter;
    
    // Variables for search
    reg [KEY_SIZE - 1:0] search_ctr;
    reg [KEY_SIZE -1:0] search_second;
    reg search_step;
    reg search_done;
    reg search_dual;
    reg [1:0][COORD_SIZE - 1:0] search_cache_a [0: CACHE_SIZE - 1];
    reg [1:0][COORD_SIZE - 1:0] search_cache_b [0: CACHE_SIZE - 1];
    reg [63:0] search_cache_areas [0: CACHE_SIZE - 1];
    reg [CACHE_SIZE - 1 :0] search_cache_free;
    reg [1:0][COORD_SIZE - 1:0] temp_a [0:1];
    reg [1:0][COORD_SIZE - 1:0] temp_b [0:1];
    reg [1:0] overflow;
    
    // Variables for verification
    reg [63:0] max_area;
    reg [63:0] par_areas [0:VERIFY_PARALLEL - 1];
    reg [VERIFY_PARALLEL - 1:0] sum_mask ;
    reg [1:0][COORD_SIZE - 1:0] upper_left_par [0:VERIFY_PARALLEL - 1]; // Smaller x and y
    reg [1:0][COORD_SIZE - 1:0] lower_right_par [0:VERIFY_PARALLEL - 1];
    reg [7:0] interior_a_par [0:VERIFY_PARALLEL - 1];
    reg [7:0] interior_b_par [0:VERIFY_PARALLEL - 1];
    reg [15:0] par_ends [0:VERIFY_PARALLEL -1];
    reg [VERIFY_PARALLEL -1:0] par_new;
    reg [VERIFY_PARALLEL - 1:0] par_running;
    reg [VERIFY_PARALLEL - 1:0] par_flags;

    // Variables used in verification loop
    reg [2:0][COORD_SIZE - 1:0] cur_ver;
    reg [2:0][COORD_SIZE - 1:0] cur_hor;
    reg [2:0][COORD_SIZE - 1:0] alt_ver;
    reg [2:0][COORD_SIZE - 1:0] alt_hor;
    reg [15:0] verif_counter;
    reg [15:0] prev_counter;
    
    // Debug Variables
    reg [31:0] debug_wait_cycles;
    reg [31:0] total_verified;
        
    assign done = (state == DONE);
    
    integer i;
    
    initial begin
        // Debug values
        debug_wait_cycles = 0;
        total_verified = 0;
    
        state = INIT;
        out_area = 0;
        max_area = 0;
        counter = 0;
                
        // Initialise vertex data
        $readmemb("output_x.bin", vx_data_x, 0, NUM_PTS - 1);
        $readmemb("output_y.bin", vx_data_y, 0, NUM_PTS - 1);

    end
    
    // Variables for caches
    reg [KEY_SIZE-1:0] cache_idx;
    reg cache_found;
    reg [1:0][KEY_SIZE-1:0] free_cache_idx;
    reg [1:0] free_cache_found;
    reg [KEY_SIZE-1:0] free_par_idx;
    reg free_par_found;
    
    always_comb begin
        // Find values in search_cache
        cache_found = 0;
        cache_idx = '0;
    
        for (int j = 0; j < CACHE_SIZE; j = j + 1) begin
            if (!cache_found && !search_cache_free[j]) begin
                cache_found = 1;
                cache_idx = j;
            end
        end
        // Find free slots in search_cache
        free_cache_found = '{1'b0, 1'b0};
        free_cache_idx = '0;
    
        for (int j = 0; j < CACHE_SIZE; j = j + 1) begin
            if (!free_cache_found[0] && search_cache_free[j]) begin
                free_cache_found[0] = 1'b1;
                free_cache_idx[0] = j;
            end else if (!free_cache_found[1] && search_cache_free[j]) begin
                free_cache_found[1] = 1'b1;
                free_cache_idx[1] = j;
            end
            
            if (free_cache_found == 2'b11)
                break;
        end
        // Find free slots in the verifier
        free_par_found = 0;
        free_par_idx = '0;
    
        for (int j = 0; j < VERIFY_PARALLEL; j = j + 1) begin   
            if (!free_par_found && !par_running[j]) begin
                free_par_found = 1;
                free_par_idx = j;
            end
        end
    end
    
    always_ff @(posedge sysclk) begin
        if (reset) begin // Reset
            state <= INIT;
            vx_addr_cur <= 0;
            vx_addr_alt <= 1;
            counter <= 0;
            out_area <= 0;
            max_area <= 0;
        end else begin
    
        case (state)
            RST: begin
                if (counter == 0) begin
                    vx_addr_cur <= 0;
                    vx_addr_alt <= 1;
                    counter <= 1;
                end else begin
                    vx_first <= '{vx_data_x[vx_addr_cur], vx_data_y[vx_addr_cur]};
                    state <= INIT;
                end
            end
            INIT: begin // Initial read from vx_data, set variables to initial values
                vx_cur <= '{vx_data_x[vx_addr_cur], vx_data_y[vx_addr_cur]};
                vx_alt <= '{vx_data_x[vx_addr_alt], vx_data_y[vx_addr_alt]};
                counter <= 1;
                state <= READ;
                he_addr_a <= 0;
                he_addr_b <= 1;
                ve_addr_a <= 0;
                ve_addr_b <= 1;
                h_edges <= 0;
                v_edges <= 0;
                counter <= 0;
                search_ctr <= 0;
                search_second <= 2;
                max_area <= 1;
                par_running <= 0;
                search_cache_free <= {CACHE_SIZE{1'b1}};
            end
            
            READ: begin // Build arrays of horizontal and vertical edges from vertex data
                if (((vx_cur == vx_first) && vx_addr_cur > 2) || (vx_addr_cur + 1) == NUM_PTS) begin // Done
                    occupied <= counter + 1;
                    vx_addr_cur <= 0;
                    vx_addr_alt <= 2;
                    state <= READ_DELAY;
                end else begin
                    // Read next values
                    vx_cur <= '{vx_data_x[vx_addr_cur], vx_data_y[vx_addr_cur]};
                    vx_alt <= '{vx_data_x[vx_addr_alt], vx_data_y[vx_addr_alt]};
                    
                    if (vx_cur[1] == vx_alt[1]) begin // Vertical edge
                        v_edges <= v_edges + 1;
                        ve_addr_a <= v_edges + 1;
                        if (vx_alt[0] < vx_cur[0]) begin
                            vertic_edges_x[ve_addr_a] <= vx_cur[1];
                            vertic_edges_ya[ve_addr_a] <= vx_alt[0];
                            vertic_edges_yb[ve_addr_a] <= vx_cur[0];
                        end else begin
                            vertic_edges_x[ve_addr_a] <= vx_cur[1];
                            vertic_edges_ya[ve_addr_a] <= vx_cur[0];
                            vertic_edges_yb[ve_addr_a] <= vx_alt[0];
                        end
                    end else begin // Horizontal edge
                        h_edges <= h_edges + 1;
                        he_addr_a <= h_edges + 1;
                        if (vx_alt[1] < vx_cur[1]) begin
                            horiz_edges_y[he_addr_a] <= vx_cur[0];
                            horiz_edges_xa[he_addr_a] <= vx_alt[1];
                            horiz_edges_xb[he_addr_a] <= vx_cur[1];
                        end else begin
                            horiz_edges_y[he_addr_a] <= vx_cur[0];
                            horiz_edges_xa[he_addr_a] <= vx_cur[1];
                            horiz_edges_xb[he_addr_a] <= vx_alt[1];
                        end
                    end
                    // Initial max area computed from max edge length, ignore initial small rectangles
                    max_area <= calc_area(vx_cur, vx_alt) > max_area ? calc_area(vx_cur, vx_alt) : max_area; 
                    vx_addr_cur <= vx_addr_cur + 1;
                    vx_addr_alt <= vx_addr_cur + 2;
                    counter <= counter + 1;
                end
            end
            
            READ_DELAY: begin
                // Initial verification variables
                cur_ver <= '{vertic_edges_x[ve_addr_a], vertic_edges_ya[ve_addr_a], vertic_edges_yb[ve_addr_a]};
                alt_ver <= '{vertic_edges_x[ve_addr_b], vertic_edges_ya[ve_addr_b], vertic_edges_yb[ve_addr_b]};
                cur_hor <= '{horiz_edges_y[he_addr_a], horiz_edges_xa[he_addr_a], horiz_edges_xb[he_addr_a]};
                alt_hor <= '{horiz_edges_y[he_addr_b], horiz_edges_xa[he_addr_b], horiz_edges_xb[he_addr_b]};
                he_addr_a <= 2;
                he_addr_b <= 3;
                ve_addr_a <= 2;
                ve_addr_b <= 3;
                verif_counter <= 0;
                par_running = 0;
                sum_mask = 0;
                par_new = 0;
                
                // Initial search variables
                vx_cur <= '{vx_data_x[vx_addr_cur], vx_data_y[vx_addr_cur]};
                vx_alt <= '{vx_data_x[vx_addr_alt], vx_data_y[vx_addr_alt]};
                search_done <= 0;
                search_dual <= 0;
                search_step <= 0;
                vx_addr_cur <= search_ctr + search_second + 1;
                vx_addr_alt <= search_ctr + search_second + 2;
                search_cache_free = {CACHE_SIZE{1'b1}};
                overflow = 0;
                state <= COMPUTE;
            end
            
            COMPUTE: begin
                // Rectangle search logic
                // search_second synchronises with the current data
                // so cur_alt == vx_data[search_ctr + 1 + search_second];
                
                search_done <= (search_ctr >= occupied);
                if (search_step && !search_done) begin // This is the only time we should be comparing only 1 rectangles per cycle
                    vx_cur <= '{vx_data_x[vx_addr_cur], vx_data_y[vx_addr_cur]};
                    vx_alt <= '{vx_data_x[vx_addr_alt], vx_data_y[vx_addr_alt]};
                    
                    vx_addr_cur <= search_ctr + search_second + 1;
                    vx_addr_alt <= search_ctr + search_second + 2;
                    search_second <= 2;
                    search_dual <= 0;
                    search_step <= 0;
                end else if (overflow != 0) begin
                    debug_wait_cycles <= debug_wait_cycles + 1;
                    if (free_cache_found == 2'b11) begin
                        if (overflow[1]) begin
                            search_cache_a[free_cache_idx[1]] <= temp_a[1];
                            search_cache_b[free_cache_idx[1]] <= temp_b[1];
                            search_cache_areas[free_cache_idx[1]] <= calc_area(temp_a[1], temp_b[1]);
                            search_cache_free[free_cache_idx[1]] <= 0;
                            overflow[1] <= 0;
                        end
                        if (overflow[0]) begin
                            search_cache_a[free_cache_idx[0]] <= temp_a[0];
                            search_cache_b[free_cache_idx[0]] <= temp_b[0];
                            search_cache_areas[free_cache_idx[0]] <= calc_area(temp_a[0], temp_b[0]);
                            search_cache_free[free_cache_idx[0]] <= 0;
                            overflow[0] <= 0;
                        end
                    end
                end else if (search_dual && !search_done) begin // Check two points at once
                
                    vx_cur <= '{vx_data_x[vx_addr_cur], vx_data_y[vx_addr_cur]};
                    vx_alt <= '{vx_data_x[vx_addr_alt], vx_data_y[vx_addr_alt]};
                    
                    vx_addr_cur <= search_ctr + search_second + 2;
                    vx_addr_alt <= search_ctr + search_second + 3;
                    search_second <= search_second + 2;
                
                    if (search_ctr + search_second >= occupied || search_ctr + search_second + 1 >= occupied) begin
                        vx_addr_cur <= search_ctr + 1;
                        vx_addr_alt <= search_ctr + 3;
                        search_ctr <= search_ctr + 1;
                        search_second <= 2;
                        search_step <= 1;
                        search_dual <= 0;
                    end
                    
                    if (search_ctr + search_second < occupied) begin
                        if (calc_area(vx_dual, vx_cur) > max_area) begin
                            if (!free_cache_found[0]) begin
                                temp_a[0] <= vx_dual;
                                temp_b[0] <= vx_cur;
                                overflow[0] <= 1'b1;
                            end else begin
                                search_cache_a[free_cache_idx[0]] <= vx_dual;
                                search_cache_b[free_cache_idx[0]] <= vx_cur;
                                search_cache_areas[free_cache_idx[0]] <= calc_area(vx_dual, vx_cur);
                                search_cache_free[free_cache_idx[0]] <= 0;
                            end
                        end
                    end
                    
                    if (search_ctr + search_second + 1 < occupied) begin
                        if (calc_area(vx_dual, vx_dual) > max_area) begin
                            if (!free_cache_found[1]) begin
                                temp_a[1] <= vx_dual;
                                temp_b[1] <= vx_alt;
                                overflow[1] <= 1'b1;
                            end else begin
                                search_cache_a[free_cache_idx[1]] <= vx_dual;
                                search_cache_b[free_cache_idx[1]] <= vx_alt;
                                search_cache_areas[free_cache_idx[1]] <= calc_area(vx_dual, vx_alt);
                                search_cache_free[free_cache_idx[1]] <= 0;
                            end
                        end
                    end
                end else if (!search_done) begin
                    
                    // Load next values and addresses (presume dual)
                    vx_cur <= '{vx_data_x[vx_addr_cur], vx_data_y[vx_addr_cur]};
                    vx_alt <= '{vx_data_x[vx_addr_alt], vx_data_y[vx_addr_alt]};
                    
                    vx_addr_cur <= search_ctr + search_second + 2;
                    vx_addr_alt <= search_ctr + search_second + 3;
                    search_second <= search_second + 2;
                    vx_dual <= vx_cur;
                    search_dual <= 1;
                    
                    if (search_ctr >= occupied || search_ctr + search_second > occupied) begin
                        vx_addr_cur <= search_ctr + 1;
                        vx_addr_alt <= search_ctr + 3;
                        search_ctr <= search_ctr + 1;
                        search_second <= 2;
                        search_dual <= 0;
                        search_step <= 1;
                    end else if (calc_area(vx_cur, vx_alt) > max_area) begin
                        if (!free_cache_found[0]) begin
                            temp_a[0] <= vx_cur;
                            temp_b[0] <= vx_alt;
                            overflow <= 2'b01;
                        end else begin
                            search_cache_a[free_cache_idx[0]] <= vx_cur;
                            search_cache_b[free_cache_idx[0]] <= vx_alt;
                            search_cache_areas[free_cache_idx[0]] <= calc_area(vx_cur, vx_alt);
                            search_cache_free[free_cache_idx[0]] <= 0;
                        end
                    end
                end
                
                // Cache into verifier registers logic
                if (free_par_found && cache_found) begin
                    total_verified <= total_verified + 1;
                    upper_left_par[free_par_idx][1] <= (search_cache_a[cache_idx][1] <  search_cache_b[cache_idx][1]) ? search_cache_a[cache_idx][1] :  search_cache_b[cache_idx][1]; // X value
                    lower_right_par[free_par_idx][1] <= (search_cache_a[cache_idx][1] <  search_cache_b[cache_idx][1]) ?  search_cache_b[cache_idx][1] : search_cache_a[cache_idx][1];
                    upper_left_par[free_par_idx][0] <= (search_cache_a[cache_idx][0] <  search_cache_b[cache_idx][0]) ? search_cache_a[cache_idx][0] :  search_cache_b[cache_idx][0]; // Y value
                    lower_right_par[free_par_idx][0] <= (search_cache_a[cache_idx][0] <  search_cache_b[cache_idx][0]) ?  search_cache_b[cache_idx][0] : search_cache_a[cache_idx][0];
                    interior_a_par[free_par_idx] <= search_cache_a[cache_idx];
                    interior_b_par[free_par_idx] <= search_cache_a[cache_idx];
                    par_areas[free_par_idx] <= search_cache_areas[cache_idx];
                    sum_mask[free_par_idx] <= 0;
                    par_running[free_par_idx] <= 1;
                    par_flags[free_par_idx] <= 0;
                    par_ends[free_par_idx] <= verif_counter;
                    search_cache_free[cache_idx] <= 1;
                    par_new[free_par_idx] <= 1;
                end
                
                // Check for new max area
                max_area <= max_area;
                for (i = 0; i < VERIFY_PARALLEL; i = i + 1) begin
                    if (par_areas[i] > max_area && sum_mask[i]) begin
                        max_area <= par_areas[i];
                    end
                    
                end
                
                sum_mask <= 0;
                
                // Prune cache with max area
                for (i = 0; i < CACHE_SIZE; i = i + 1) begin
                    if (search_cache_areas[i] <= max_area) begin
                        search_cache_free[i] <= 1;
                    end
                end
                
                // Parallel verifier logic
                
                // Load for next cycle
                cur_ver <= '{vertic_edges_x[ve_addr_a], vertic_edges_ya[ve_addr_a], vertic_edges_yb[ve_addr_a]};
                alt_ver <= '{vertic_edges_x[ve_addr_b], vertic_edges_ya[ve_addr_b], vertic_edges_yb[ve_addr_b]};
                cur_hor <= '{horiz_edges_y[he_addr_a], horiz_edges_xa[he_addr_a], horiz_edges_xb[he_addr_a]};
                alt_hor <= '{horiz_edges_y[he_addr_b], horiz_edges_xa[he_addr_b], horiz_edges_xb[he_addr_b]};
                
                // Loop counter
                prev_counter <= verif_counter;
                if (verif_counter >= v_edges && verif_counter >= h_edges) begin
                    verif_counter <= 0;
                    he_addr_a <= 0;
                    ve_addr_b <= 1;
                    ve_addr_a <= 0;
                    he_addr_b <= 1;
                end else begin
                    verif_counter <= verif_counter + 2;
                    he_addr_a <= he_addr_a + 2;
                    ve_addr_b <= ve_addr_b + 2;
                    ve_addr_a <= ve_addr_a + 2;
                    he_addr_b <= he_addr_b + 2;
                end
                
                
                for (i = 0; i < VERIFY_PARALLEL; i = i + 1) begin
                    if (par_running[i]) begin
                        if (verif_counter < v_edges) begin // cur_ver
                            if ((cur_ver[2] < lower_right_par[i][1]) && (cur_ver[2] > upper_left_par[i][1])) begin
                                if ((cur_ver[1] < lower_right_par[i][0]) && (cur_ver[0] > upper_left_par[i][0])) begin
                                    // Set flag here
                                    par_flags[i] <= 1'b1;
                                end
                            end
                            if ((cur_ver[1] <= (upper_left_par[i][0] + 1)) && (cur_ver[0] >= (upper_left_par[i][0] + 1))) begin
                                if (cur_ver[2] <= upper_left_par[i][1]) begin
                                    interior_a_par[i] <= interior_a_par[i] + 1;
                                end
                            end
                        end
                        
                        if ((verif_counter + 1) < v_edges) begin // alt_ver
                            if ((alt_ver[2] < lower_right_par[i][1]) && (alt_ver[2] > upper_left_par[i][1])) begin
                                if ((alt_ver[1] < lower_right_par[i][0]) && (alt_ver[0] > upper_left_par[i][0])) begin
                                    par_flags[i] <= 1'b1;
                                end
                            end
                            if ((alt_ver[1] <= (upper_left_par[i][0] + 1)) && (alt_ver[0] >= (upper_left_par[i][0] + 1))) begin
                                if (alt_ver[2] <= upper_left_par[i][1]) begin
                                    interior_b_par[i] <= interior_b_par[i] + 1;
                                end
                            end
                        end
                        
                        if (verif_counter < h_edges) begin // cur_hor
                            if ((cur_hor[2] < lower_right_par[i][0]) && (cur_hor[2] > upper_left_par[i][0])) begin
                                if ((cur_hor[1] < lower_right_par[i][1]) && (cur_hor[0] > upper_left_par[i][1])) begin
                                    par_flags[i] <= 1'b1;
                                end
                            end
                        end
                        
                        if ((verif_counter + 1) < h_edges) begin // alt_hor
                            if ((alt_hor[2] < lower_right_par[i][0]) && (alt_hor[2] > upper_left_par[i][0])) begin
                                if ((alt_hor[1] < lower_right_par[i][1]) && (alt_hor[0] > upper_left_par[i][1])) begin
                                    par_flags[i] <= 1'b1;
                                end
                            end
                        end
                        
                        // Each verification stops when par_ends[i] == prev_counter, par_new stops them from always terminating after 1 cycle
                        if (par_new[i]) begin
                            par_new[i] <= 0;
                        end
                        
                        if (par_flags[i] == 1'b1) begin // Invalid
                            par_running[i] <= 0;
                        end else if ((par_ends[i] == prev_counter) && !par_new[i]) begin // Checked all edges
                            par_running[i] <= 0;
                            if (interior_a_par[i][0] ^ interior_b_par[i][0]) begin // Valid
                                sum_mask[i] <= 1;
                            end
                        end
                    end
                end
                
                // Check for finish condition
                if (search_done && (par_running == 0) && (search_cache_free == {CACHE_SIZE{1'b1}})) begin
                    out_area <= max_area;
                    state <= DONE;
                end
            end
            
            DONE: ;
            default: ;
        endcase
        end
    end    
    
    
    
    function automatic int calc_area(
            input logic [1:0][COORD_SIZE - 1: 0] a,
            input logic [1:0][COORD_SIZE - 1: 0] b
        );
        int y = a[0] > b[0] ? (a[0] - b[0] + 1) : (b[0] - a[0] + 1);
        int x = a[1] > b[1] ? (a[1] - b[1] + 1) : (b[1] - a[1] + 1);
        return x * y;
    endfunction
endmodule
