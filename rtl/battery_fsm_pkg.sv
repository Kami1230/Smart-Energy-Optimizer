package battery_fsm_pkg;

// --------------------------fixed-point-format------------------------
// Q8.8 signed fixed-point: 8 integer bits, 8 fractional bits
// real _value = fixed_value /256.0

    typedef logic signed [15:0] fixed_t;
    localparam int SCALE = 256

// ---------------------------state encoding-----------------------------
    typedef enum logic [2:0] {
        IDLE        = 3'd0,
        CHARGING    = 3'd1,
        DISCHARGIN  = 3'd2,
        LOAD_SHED   = 3'd3,
        FAULT       = 3'd4
    } state_t;

// ------------------------threshbolds (Q8.8)----------------------------
    localparam fixed_t SOC_FULL             = 16'sd230;  // 0.90
    localparam fixed_t SOC_LOW              = 16'sd77;   // 0.30
    localparam fixed_t SOC_CRITICAL         = 16'sd26;   // 0.10
    localparam fixed_t SURPLUS_THRESHOLD    = 16'sd512;  // 2.00 A
    localparam fixed_t HIGH_DEMAND          = 16'sd1280; // 5.00 A
endpackage