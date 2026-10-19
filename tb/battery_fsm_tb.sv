`timescale 1ns/1ps
import battery_fsm_pkg::*;

module battery_fsm_tb;
    localparam int N = 201;                // If N > file -> extral lines read as x
    localparam int LAT = 2;                // pipeline latency: state reg + rate-limiter reg
    localparam int TOL = 16;               // LSBs, absorbs 26 vs 25.6 step drift
    int diff;

    logic clk = 0, rst_n = 0;
    fixed_t surplus, soc, battery_cmd;
    logic charger_conn, load_conn, fault_detect = 0, fault_clear = 0;
    state_t state;
    
    // Memory of Simulink data
    fixed_t surplus_mem [0: N-1];
    fixed_t soc_mem     [0: N-1];
    fixed_t cmd_mem     [0: N-1];           // Simulink reference
    
    battery_fsm dut (.*);
    always #5 clk = ~clk;
    
    int errors = 0;
    
    initial begin
        $readmemh("vectors/vec_surplus.hex",         surplus_mem);
        $readmemh("vectors/vec_soc.hex",             soc_mem);
        $readmemh("vectors/vec_battery_cmd.hex",     cmd_mem);
        #12 rst_n = 1;

        for (int i = 0; i < N; i++) begin
            @(negedge clk);
            surplus     = surplus_mem[i];
            soc         = soc_mem[i];
            charger_conn = (surplus > 0);
            load_conn   = (surplus < 0);
            #1;                             // lets combinational outputs settle

            if (i >= LAT) begin
                diff = $signed(battery_cmd) - $signed(cmd_mem[i-LAT]);
                if ((^battery_cmd === 1'bx) || diff > TOL || diff < -TOL) begin
                    errors++;
                    $display("MISMATCH i=%0d cmd=%h expected=%h state=%0d", i, battery_cmd, cmd_mem[i-LAT], state);
                end
            end
        end
        $display("Done: %0d mismatches out of %d samples", errors, N);
        $finish;
    end
endmodule