# AHB-to-APB Bridge Controller

## Project Overview

This project implements and verifies an AHB-to-APB bridge controller in SystemVerilog. The bridge connects a high-speed AHB-side interface to a lower-speed APB peripheral interface and converts AHB read/write transfers into APB setup and enable phase transactions.

The design acts as an AHB slave and an APB master/controller. It supports address decoding, pipelined AHB signal handling, single transfers, and burst-style AHB traffic.

## Folder Structure

```text
AHB_APB/
├── common/
│   ├── ahb_apb_pkg.sv
│   └── ahb_apb_if.sv
├── rtl/
│   ├── ahb_slave.sv
│   ├── apb_controller.sv
│   └── bridge_top.sv
├── tb/
│   ├── ahb_master_bfm.sv
│   ├── apb_peripheral.sv
│   ├── ahb_apb_checker.sv
│   └── top_tb.sv
├── sim/
│   └── vcs_filelist.f
└── docs/
    └── CHANGES.md
RTL Design

The RTL contains three main design blocks:

ahb_slave.sv: Handles AHB-side transaction validation, address decoding, and pipelining.
apb_controller.sv: Implements the FSM that generates APB setup and enable phases.
bridge_top.sv: Connects the AHB-side logic and APB controller as the top-level DUT.
Verification Environment

The verification environment includes:

AHB master BFM
APB peripheral model
Self-checking SystemVerilog testbench
Protocol assertions
Functional coverage
Synopsys VCS regression flow
Verified Scenarios

The testbench validates six directed scenarios:

Reset and idle behavior
Single write to APB peripheral region 0
Single read/readback from APB peripheral region 0
Invalid address no-select behavior
Single write/readback to APB peripheral region 2
Burst write transaction to APB peripheral region 1
Running Simulation in Synopsys VCS

Go to the simulation directory:

cd sim

Compile:

vcs -full64 -sverilog -timescale=1ns/1ps \
  -debug_access+all \
  +vcs+lic+wait \
  -assert svaext \
  -cm line+cond+fsm+tgl+branch+assert \
  -cm_dir simv.vdb \
  -l compile.log \
  -f vcs_filelist.f \
  -top top_tb \
  -o simv

Run simulation:

./simv -cm line+cond+fsm+tgl+branch+assert -cm_dir simv.vdb -l sim.log

Generate coverage report:

urg -dir simv.vdb -report urgReport

Check results:

grep -E "ERROR|Fatal|protocol|Readback|PASS|FAIL|COV" sim.log

Expected result:

[PASS] Scenario 1: reset/idle completed
[PASS] Scenario 2: single write to peripheral 0 completed
[TB] Readback HRDATA = 0xdeadbeef
[PASS] peripheral0 write-read actual=0xdeadbeef expected=0xdeadbeef
[PASS] Scenario 4: invalid address produced no APB select
[PASS] peripheral2 write-read actual=0xcafebabe expected=0xcafebabe
[PASS] Scenario 6: burst write to peripheral 1 completed
[TB] PASS: all directed scenarios completed
[COV] AHB-APB functional coverage = 97.92%
Results
Tool: Synopsys VCS
Testbench: Self-checking SystemVerilog testbench
Assertions: AHB/APB protocol checks
Functional coverage: 97.92%
Final simulation status: PASS
Key Debug Fixes

During verification, the following RTL and testbench issues were identified and fixed:

Invalid address stimulus preventing APB peripheral selection
Bridge top-level port wiring issues
Inferred latch risks in APB controller logic
APB PSEL/PENABLE sequencing issue
Missing real APB peripheral model
AHB master BFM protocol violation where transfers advanced without respecting HREADY
Resume Summary

Designed and verified an AHB-to-APB bridge controller in SystemVerilog with FSM-based APB control, address decoding, pipelined AHB signal handling, protocol assertions, and functional coverage. Built a self-checking VCS testbench that validated six transfer scenarios and achieved 97.92% functional coverage.
