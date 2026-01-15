
// All parameters here
// UART uses 8 bits + 1 parity (even)
package params;
    // Number of parallel verifiers
    localparam VERIFY_PARALLEL = 32;
    
    // Cache size for search
    localparam CACHE_SIZE = 30;
    
    // Array parameters for BRAM
    // Puzzle input: NUM_PTS = 500, COORD_SIZE = 20, KEY_SIZE = 10
    localparam NUM_PTS = 500; // Max number of pts
    localparam COORD_SIZE = 20; // Bits per x/y value, must be multiple of 2
    localparam KEY_SIZE = 10; // Bits for pointer variable

    // Parameters for UART communication
    localparam CLK_FREQ  = 12_000_000;
    localparam BAUD_RATE = 9_600;
    
    // Cycles per millisecond
    localparam MILLIS = CLK_FREQ / 1_000;

endpackage
