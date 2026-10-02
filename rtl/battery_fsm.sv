import battery_fsm_pkg::*;

module battery_fsm (
    input logic     clk,
    input logic     rst_n,

    input fixed_t surplus,      // Ipv - Iload, Q8.8
    input fixed_t soc,          // state of charge, Q8.8

    // Boolean condtions for transition table
    input logic charger_conn,   // charger physically connected
    input logic load_conn,      // load physically connected
    input logic fault_detect,    // critical error (over-temp/over-volt/HW fail)
    input logic fault_clear,    // manual/auto clear-fault command

    output state_t  state,         // current state
    output fixed_t  battery_cmd    // + = charge, - = discharge, 0 = idle/shed
);

    state_t next_state;

    // derived condtions
    logic battery_full, battery_low, battery_critical, battery_has_charge;
    logic surplus_pos, surplus_neg, high_demand;

    assign battery_full         = (soc >= SOC_FULL);
    assign battery_low          = (soc < SOC_LOW) && (soc >= SOC_CRITICAL);
    assign battery_critical     = (soc < SOC_CRITICAL);
    assign battery_has_charge   = (soc > SOC_CRITICAL);
    assign surplus_pos          = (surplus > SURPLUS_THRESHOLD);
    assign surplus_neg          = (surplus < -SURPLUS_THRESHOLD);
    assign high_demand          = (surplus < -HIGH_DEMAND); // large deficit = high demand

    // --------------------------STATE REGISTER--------------------------/
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else        state <= next_state;
    end

    // -------------------------NEXT STATE LOGIC--------------------------/
    always_comb begin           // regultates when input changes - clk independent
        next_state = state;     // stay on current state excpt condition below fires

        // Fault has priority
        if (fault_detect && state != FAULT) begin
            next_state = FAULT;
        end else begin
            case (state)
                IDLE: begin 
                    if (charger_conn && !battery_full)
                        next_state = CHARGING;
                    else if (load_conn && battery_has_charge)
                        next_state = DISCHARGING;
                end

                CHARGING: begin
                    if (!charger_conn || battery_full )
                        next_state = IDLE;
                end

                DISCHARGING: begin
                    if (!load_conn || battery_critical)
                        next_state = IDLE;
                    else if (battery_low && high_demand)
                        next_state = LOAD_SHED;
                end

                LOAD_SHED: begin
                    if (charger_conn)
                        next_state = CHARGING;
                    else if (battery_critical)
                        next_state = IDLE;
                    else if (!battery_low || !high_demand)
                        next_state = DISCHARGING;
                end

                FAULT: begin
                    if (!fault_detect && fault_clear)
                        next_state = IDLE;
                end

                default: next_state = IDLE; // backup for unreachable states
            endcase
        end
    end

    // ----------------------OUTPUT LOGIC(Moore)----------------------------/
    always_comb begin
        case(state)
            CHARGING:    battery_cmd = surplus; // command = available surplus
            DISCHARGING: battery_cmd = surplus; // negative surplus = discharge amount
            default:     battery_cmd = '0;      // IDLE, LOAD_SHED, FAULE: no command
        endcase
    end
endmodule