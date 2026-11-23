# Smart Energy Optimizer

[![MATLAB](https://img.shields.io/badge/MATLAB-Simulink-orange?logo=mathworks&logoColor=white)](https://www.mathworks.com/products/simulink.html)
[![SystemVerilog](https://img.shields.io/badge/HDL-SystemVerilog-blue)](https://github.com/Kami1230/Smart-Energy-Optimizer)
[![Status](https://img.shields.io/badge/V1-In%20Progress-yellow)](https://github.com/Kami1230/Smart-Energy-Optimizer)

A five-state battery and microgrid controller for a simulated microgrid or event venue. It decides when to charge, discharge, shed non-critical load, remain idle, or enter a fault state.

The project is organized into three stages:

| Version | Status | Focus |
|---|---|---|
| V1 - Simulink and SystemVerilog | **IN PROGRESS** | Modeling, RTL, fixed-point arithmetic, verification |
| V2 - Arduino on the bench | **PLANNED** | Embedded C, serial regression, sensors, and power hardware |
| V3 - Real-world calibration | **PLANNED / NOT FULLY SCOPED** | Calibrating the Simulink model against physical measurements |

## Current Status

V1 combines a Simulink microgrid model with a SystemVerilog controller using signed Q8.8 power and state-of-charge values. The output is a rate-limited battery command.

| Milestone | Status |
|---|---|
| M1 - Simulink plant, reference controller, and logging | **DONE** |
| M2 - Five-state RTL FSM and regression tests | **DONE** |
| M3 - Closed-loop plant scenarios and plots | **NOT STARTED** |

Current verification results:

- **99 directed checks passed**
- **0 mismatches across 199 compared samples**
- The first two of 201 loaded samples are skipped for the two-clock pipeline latency; tolerance is +/-16 LSB

## Verification Waveforms

![Fault command cutoff](docs/waveforms/fault-command-cutoff.png)

**Fault cutoff:** entering `FAULT` immediately forces `battery_cmd` to zero.

![High-demand boundary](docs/waveforms/high-demand-boundary.png)

**High-demand boundary:** `LOAD_SHED` begins only when the deficit moves past the configured threshold.

![Command ramp](docs/waveforms/command-ramp.png)

**Command ramp:** the Q8.8 battery command advances toward its target at the configured rate.

## Controller Specification

The five states are `IDLE`, `CHARGING`, `DISCHARGING`, `LOAD_SHED`, and `FAULT`.
The Simulink model provides the plant and reference output; exported vectors verify the RTL FSM and its battery-command rate limiter.

```mermaid
stateDiagram-v2
    [*] --> IDLE
    IDLE --> CHARGING: charger connected, not full, surplus > +2 A
    IDLE --> DISCHARGING: load connected, SoC above critical, surplus < -2 A
    CHARGING --> IDLE: charger disconnected, full, or surplus <= +2 A
    DISCHARGING --> IDLE: load disconnected, SoC critical, or surplus >= -2 A
    DISCHARGING --> LOAD_SHED: low SoC and high demand
    LOAD_SHED --> CHARGING: charger connected, not full, surplus > +2 A
    LOAD_SHED --> IDLE: SoC critical
    LOAD_SHED --> DISCHARGING: deficit remains and battery or demand recovers
    IDLE --> FAULT: fault detected
    CHARGING --> FAULT: fault detected
    DISCHARGING --> FAULT: fault detected
    LOAD_SHED --> FAULT: fault detected
    FAULT --> IDLE: fault absent and clear asserted
```

Fault detection has priority over normal operation and immediately sets the battery command to zero.

### Power-decision rules

- `surplus = solar generation - load demand`
- Positive battery command charges the battery; negative battery command discharges it.
- The inclusive dead zone is `-2.00 A <= surplus <= +2.00 A`, where the target command is zero.
- `CHARGING` can only produce a positive command above `+2.00 A`.
- `DISCHARGING` can only produce a negative command below `-2.00 A`.
- High demand means a net deficit greater than `5.00 A` (`surplus < -5.00 A`), not raw load current.

### Shared Q8.8 values

All three versions will use the same transition table, constants, and exported test vectors.

| Constant | Integer value | Engineering value |
|---|---:|---:|
| `SOC_FULL` | 230 | approximately 0.90 |
| `SOC_LOW` | 77 | approximately 0.30 |
| `SOC_CRITICAL` | 26 | approximately 0.10 |
| `SURPLUS_THRESHOLD` | +/-512 | +/-2.00 A |
| `HIGH_DEMAND` | 1280 | 5.00 A |
| Command step | 26 per clock | approximately 0.102 A per clock |

For Q8.8 values: `real value = integer value / 256`.

## Known Open Items

- The M3 closed-loop plant simulation has not started.

## Roadmap

### V1 - Simulink and SystemVerilog

Build the closed-loop testbench plant and run six scenarios:

1. High solar and low load
2. Low solar and high load
3. Battery nearly full
4. Battery nearly empty
5. Rapidly changing demand
6. Extended low generation

V1 is complete when these scenarios produce plots for SoC, surplus, state, and command, and the repository is tagged `v1.0-sim`.

### V2 - Arduino on the Bench

- Port the V1 FSM and Q8.8 contract to C.
- Run the existing V1 vectors through the Arduino over serial and compare its results with the RTL.
- Add bench controls, state indicators, current sensing, load switching, PWM output, and serial logging.
- Connect the controller to safe, low-power battery and load hardware with real sensors.

### V3 - Closing the Loop with the Real World

This stage is planned but not fully scoped. The goal is to:

- Record measurements from the V2 hardware.
- Compare the physical measurements with the Simulink results.
- Calibrate the Simulink plant parameters against the real system.
- Possibly use a real single-cell PV panel as the source.

Later stretch goals include Stateflow, wind generation, load-priority tiers, and a results dashboard.

## Run the V1 Tests

Requirements: Icarus Verilog for RTL simulation and MATLAB/Simulink for the model and vector export.
Run all commands from the repository root because the testbenches load `vectors/*.hex` using relative paths.

### Directed FSM test

```bash
iverilog -g2012 -o directed.vvp rtl/battery_fsm_pkg.sv rtl/battery_fsm.sv tb/battery_fsm_directed_tb.sv
vvp directed.vvp
```

Expected summary:

```text
99 checks, 0 failures
ALL CHECKS PASSED
```

### Simulink-vector comparison

```bash
iverilog -g2012 -o tb.vvp rtl/battery_fsm_pkg.sv rtl/battery_fsm.sv tb/battery_fsm_tb.sv
vvp tb.vvp
```

Expected result: **0 mismatches across 199 compared samples**. The first two samples are skipped while the pipeline fills.

### Regenerate the vectors

Open `SmartEnergyOptimizer.prj` in MATLAB and run:

```matlab
run("scripts/export_fsm_vectors.m")
```

## Repository Layout

```text
SmartEnergyOptimizer.slx     Simulink plant and reference controller
rtl/                        SystemVerilog controller
tb/                         RTL testbenches
vectors/                    Shared Q8.8 regression vectors
scripts/                    MATLAB vector-export script
docs/                       Design notes and waveform results
archive/                    Previous models and retired test scaffolds
fw/                         Arduino firmware (planned)
```

The V1 tag `v1.0-sim` will define the controller specification that V2 must match and the simulation baseline used for V3 calibration.
