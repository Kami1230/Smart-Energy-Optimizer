`timescale 1ns/1ps
import battery_fsm_pkg::*;

// Directed (self-checking) tests for battery_fsm.
// One scenario per transition in the FSM design table, plus boundary and
// command-output checks. Prints FAIL lines for real mismatches and REVIEW
// lines for behavior that needs a design decision.

module battery_fsm_directed_tb;
    logic   clk = 0, rst_n = 0;
    fixed_t surplus = 0, soc = 16'sd128;
    logic   charger_conn = 0, load_conn = 0, fault_detect = 0, fault_clear = 0;
    state_t state;
    fixed_t battery_cmd;

    battery_fsm dut (.*);
    always #5 clk = ~clk;

    int errors = 0, reviews = 0, checks = 0;

    // Scenario values (Q8.8)
    localparam fixed_t SOC_MID = 16'sd128;    // 0.50
    localparam fixed_t SOC_LOW_ZONE = 16'sd50;// between CRITICAL and LOW
    localparam fixed_t I_CHG   = 16'sd1024;   // +4 A surplus
    localparam fixed_t I_DIS   = -16'sd1024;  // -4 A deficit (below HIGH_DEMAND)
    localparam fixed_t I_HIGH  = -16'sd1536;  // -6 A deficit (above HIGH_DEMAND)

    // ---------------------------------------------------------------- helpers
    // Inputs change on the falling edge; one tick = one rising edge passes,
    // so the registered state has updated when tick returns.
    task automatic tick;
        @(negedge clk);
    endtask

    task automatic ticks(input int n);
        repeat (n) @(negedge clk);
    endtask

    function automatic string sname(input state_t s);
        case (s)
            IDLE:        return "IDLE";
            CHARGING:    return "CHARGING";
            DISCHARGING: return "DISCHARGING";
            LOAD_SHED:   return "LOAD_SHED";
            FAULT:       return "FAULT";
            default:     return "UNKNOWN";
        endcase
    endfunction

    task automatic expect_state(input state_t exp, input string msg);
        checks++;
        if (state !== exp) begin
            errors++;
            $display("FAIL   %0s: got %0s, expected %0s", msg, sname(state), sname(exp));
        end
    endtask

    task automatic expect_cmd(input fixed_t exp, input string msg);
        checks++;
        if (battery_cmd !== exp) begin
            errors++;
            $display("FAIL   %0s: cmd=%0d, expected %0d", msg, $signed(battery_cmd), $signed(exp));
        end
    endtask

    task automatic do_reset;
        rst_n = 0;
        charger_conn = 0; load_conn = 0; fault_detect = 0; fault_clear = 0;
        surplus = 0; soc = SOC_MID;
        tick; tick;
        rst_n = 1;
        tick;
    endtask

    // Reusable "get me into state X" setups (each also checks the entry)
    task automatic enter_charging;
        do_reset;
        surplus = I_CHG; charger_conn = 1;
        tick;
        expect_state(CHARGING, "setup IDLE->CHARGING");
    endtask

    task automatic enter_discharging;
        do_reset;
        surplus = I_DIS; load_conn = 1;
        tick;
        expect_state(DISCHARGING, "setup IDLE->DISCHARGING");
    endtask

    task automatic enter_load_shed;
        enter_discharging;
        soc = SOC_LOW_ZONE; surplus = I_HIGH;   // low battery + high demand
        tick;
        expect_state(LOAD_SHED, "setup DISCHARGING->LOAD_SHED");
    endtask

    // ------------------------------------------------------------------ tests
    initial begin
        $dumpfile("directed.vcd");
        $dumpvars(0, battery_fsm_directed_tb);
        $display("=== A. IDLE transitions ===");

        do_reset; ticks(3);
        expect_state(IDLE, "A1 IDLE holds with nothing connected");

        do_reset; charger_conn = 1; surplus = I_CHG; tick;
        expect_state(CHARGING, "A2 IDLE->CHARGING (charger, not full)");

        do_reset; load_conn = 1; surplus = I_DIS; tick;
        expect_state(DISCHARGING, "A3 IDLE->DISCHARGING (load, has charge)");

        do_reset; charger_conn = 1; load_conn = 1; tick;
        expect_state(CHARGING, "A4 charger+load both connected -> CHARGING first");

        do_reset; charger_conn = 1; soc = SOC_FULL; tick;
        expect_state(IDLE, "A5a charger + full battery stays IDLE");
        load_conn = 1; tick;
        expect_state(DISCHARGING, "A5b charger + full + load -> DISCHARGING");

        do_reset; charger_conn = 1; soc = SOC_FULL - 1; tick;
        expect_state(CHARGING, "A6 soc just below FULL still charges");

        do_reset; load_conn = 1; soc = SOC_CRITICAL; tick;
        expect_state(IDLE, "A7a load but soc==CRITICAL: no usable charge");
        soc = SOC_CRITICAL + 1; tick;
        expect_state(DISCHARGING, "A7b load and soc just above CRITICAL");

        do_reset; fault_detect = 1; tick;
        expect_state(FAULT, "A8 IDLE->FAULT");

        $display("=== B. CHARGING transitions ===");

        enter_charging; ticks(3);
        expect_state(CHARGING, "B1 CHARGING holds while not full");

        enter_charging; charger_conn = 0; tick;
        expect_state(IDLE, "B2 CHARGING->IDLE (charger disconnected)");

        enter_charging; soc = SOC_FULL - 1; tick;
        expect_state(CHARGING, "B3a soc==FULL-1 keeps charging");
        soc = SOC_FULL; tick;
        expect_state(IDLE, "B3b CHARGING->IDLE (battery full at soc==FULL)");

        enter_charging; fault_detect = 1; tick;
        expect_state(FAULT, "B4 CHARGING->FAULT");

        $display("=== C. DISCHARGING transitions ===");

        enter_discharging; ticks(3);
        expect_state(DISCHARGING, "C1 DISCHARGING holds normally");

        enter_discharging; load_conn = 0; tick;
        expect_state(IDLE, "C2 DISCHARGING->IDLE (load disconnected)");

        enter_discharging; soc = SOC_CRITICAL + 1; tick;
        expect_state(DISCHARGING, "C3a soc==CRITICAL+1 keeps discharging");
        soc = SOC_CRITICAL; tick;
        expect_state(IDLE, "C3b DISCHARGING->IDLE at soc==CRITICAL (empty)");

        enter_discharging; soc = SOC_CRITICAL - 1; tick;
        expect_state(IDLE, "C3c DISCHARGING->IDLE below CRITICAL");

        enter_discharging; soc = SOC_LOW - 1; surplus = I_HIGH; tick;
        expect_state(LOAD_SHED, "C4 DISCHARGING->LOAD_SHED (low + high demand)");

        enter_discharging; soc = SOC_LOW - 1; tick;
        expect_state(DISCHARGING, "C5 low battery, normal demand: keeps discharging");

        enter_discharging; soc = SOC_LOW; surplus = I_HIGH; tick;
        expect_state(DISCHARGING, "C6 high demand, soc==LOW (not low): keeps discharging");

        enter_discharging; soc = SOC_LOW - 1; surplus = -HIGH_DEMAND; tick;
        expect_state(DISCHARGING, "C7a deficit == HIGH_DEMAND is not high demand");
        surplus = -HIGH_DEMAND - 1; tick;
        expect_state(LOAD_SHED, "C7b deficit just past HIGH_DEMAND -> LOAD_SHED");

        enter_discharging; fault_detect = 1; tick;
        expect_state(FAULT, "C8 DISCHARGING->FAULT");

        $display("=== D. LOAD_SHED transitions ===");

        enter_load_shed; ticks(3);
        expect_state(LOAD_SHED, "D1 LOAD_SHED holds (low + high demand)");

        enter_load_shed; charger_conn = 1; tick;
        expect_state(CHARGING, "D2 LOAD_SHED->CHARGING (charger connected)");

        enter_load_shed; soc = SOC_CRITICAL - 1; tick;
        expect_state(IDLE, "D3a LOAD_SHED->IDLE below CRITICAL");

        enter_load_shed; soc = SOC_CRITICAL; tick;
        expect_state(IDLE, "D3b LOAD_SHED->IDLE at soc==CRITICAL");

        enter_load_shed; soc = SOC_LOW; tick;
        expect_state(DISCHARGING, "D4 LOAD_SHED->DISCHARGING (battery recovers)");

        enter_load_shed; surplus = I_DIS; tick;
        expect_state(DISCHARGING, "D5 LOAD_SHED->DISCHARGING (demand decreases)");

        enter_load_shed; fault_detect = 1; tick;
        expect_state(FAULT, "D6 LOAD_SHED->FAULT");

        enter_load_shed; charger_conn = 1; soc = SOC_CRITICAL - 1; tick;
        expect_state(CHARGING, "D7 priority: charger beats critical");

        $display("=== E. FAULT behavior ===");

        enter_charging; fault_detect = 1; tick; ticks(3);
        expect_state(FAULT, "E1 FAULT holds while error present");
        fault_detect = 0; ticks(3);
        expect_state(FAULT, "E2 FAULT holds after error drops, until cleared");
        fault_clear = 1; tick;
        expect_state(IDLE, "E3 FAULT->IDLE (clear command and safe)");

        enter_charging; fault_detect = 1; tick;
        fault_clear = 1; tick;
        expect_state(FAULT, "E4a clear ignored while error still present");
        fault_detect = 0; tick;
        expect_state(IDLE, "E4b clears once error is gone");

        $display("=== F. Reset mid-run ===");

        enter_charging; ticks(10);
        rst_n = 0; #1;
        expect_state(IDLE, "F1a async reset from CHARGING: state");
        expect_cmd(16'sd0, "F1b async reset from CHARGING: cmd");
        rst_n = 1; tick;

        enter_charging; fault_detect = 1; tick;
        rst_n = 0; #1;
        expect_state(IDLE, "F2 async reset from FAULT");
        rst_n = 1; tick;

        $display("=== G. battery_cmd behavior ===");

        enter_charging; ticks(45);
        expect_cmd(I_CHG, "G1 CHARGING: cmd ramps to +target");

        enter_discharging; ticks(45);
        expect_cmd(I_DIS, "G2 DISCHARGING: cmd ramps to -target");

        enter_charging; ticks(45); charger_conn = 0; ticks(45);
        expect_cmd(16'sd0, "G3 cmd returns to 0 after leaving CHARGING");

        enter_discharging; ticks(45);
        soc = SOC_LOW_ZONE; surplus = I_HIGH; tick; ticks(60);
        expect_state(LOAD_SHED, "G4a still in LOAD_SHED");
        expect_cmd(16'sd0, "G4b LOAD_SHED: cmd goes to 0");

        enter_charging; ticks(45);
        expect_cmd(I_CHG, "G5a pre-fault cmd at target");
        fault_detect = 1; tick;
        expect_state(FAULT, "G5b in FAULT");
        expect_cmd(16'sd0, "G5c FAULT cuts cmd immediately (no ramp-down)");

        // Design-decision items: print REVIEW instead of FAIL
        enter_charging; surplus = I_DIS; ticks(45);
        if (battery_cmd[15] === 1'b1) begin
            reviews++;
            $display("REVIEW CHARGING state is commanding discharge (cmd=%0d) when surplus goes negative", $signed(battery_cmd));
        end

        enter_discharging; surplus = I_CHG; ticks(45);
        if (battery_cmd[15] === 1'b0 && battery_cmd !== 16'sd0) begin
            reviews++;
            $display("REVIEW DISCHARGING state is commanding charge (cmd=%0d) when surplus goes positive", $signed(battery_cmd));
        end

        enter_charging; surplus = 16'sd100; ticks(5);
        if (battery_cmd !== 16'sd0) begin
            reviews++;
            $display("REVIEW surplus 0.4 A (< SURPLUS_THRESHOLD) still produces cmd=%0d: dead-zone not applied", $signed(battery_cmd));
        end

        $display("-----------------------------------------------");
        $display("%0d checks, %0d failures, %0d review items", checks, errors, reviews);
        if (errors == 0) $display("ALL CHECKS PASSED");
        $finish;
    end
endmodule