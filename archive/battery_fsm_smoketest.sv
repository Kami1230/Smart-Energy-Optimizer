import battery_fsm_pkg::*;
module battery_fsm_smoketest
    initial begin
        $dumpfile("smoketest.vcd");
        $dumpvars(0, battery_fsm_smoketest);

        rst_n = 0;
        #12 rst_n = 1;

        // test 1: charger connects, surplus positive -> CHARGING
        #10 surplus = 16'sd1024;      // +4.0 A (above the +2.0 A threshold)
        charger_conn = 1;
        #20 charger_conn = 0;
        surplus = 0;

        // test 2: load connects, deficit -> DISCHARGING
        #10 surplus = -16'sd1024;     // -4.0 A
        load_conn = 1;

        #50 $finish;
    end
endmodule