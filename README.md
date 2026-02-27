# Komandara — A RISC-V CPU, Vibe-Coded from Spec to Silicon

**Komandara** is an open-source, from-scratch RISC-V CPU design project with a twist: **the in-house CPU/SoC RTL is written by AI.** The human stays on the system engineering side — defining the architecture, writing the specifications, setting the constraints, and steering the direction — while AI pair-programmers (e.g. ChatGPT, Gemini) produce the core SystemVerilog, testbenches, build scripts, and verification infrastructure.

> **The human does not touch the code.** The K10 CPU/SoC implementation in this repository is AI-generated, guided only by natural-language architectural decisions and spec references.

This is an experiment in **vibe coding** applied to hardware design: can a human systems architect, armed with the right specs and a clear vision, produce a working, verified RISC-V core without writing a single line of Verilog? Third-party vendor debug IP remains vendor-owned.

---

## Current Focus: K10

**K10** is the first-generation core and the current focus of all development.

| Feature | K10 Spec |
|---|---|
| **ISA** | RV32IMAC_Zicsr_Zifencei |
| **Pipeline** | 5-Stage Classic (In-Order): IF → ID → EX → MEM → WB |
| **Privilege Modes** | Machine (M) + User (U) |
| **Memory Model** | Physical Addressing Only (No MMU) |
| **Memory Protection** | PMP (Physical Memory Protection, 16 regions) |
| **Unaligned Access** | Hardware support (LSU splits into 2 aligned bus ops) |
| **Bus Protocol** | AXI4-Lite (SoC interconnect) |
| **Memory** | Parametric BRAM (infers FPGA BRAM, configurable size via FuseSoC) |
| **Target OS** | RTOS (FreeRTOS, Zephyr) or Bare-metal |
| **Coding Standard** | IEEE 1800-2017 SystemVerilog, ASIC-style |

### Reference Specifications

All design logic strictly adheres to the ratified RISC-V specifications:

- **Unprivileged ISA:** `spec/riscv-spec-20191213.txt` (RV32IMAC_Zicsr_Zifencei)
- **Privileged Architecture:** `spec/riscv-privileged-20211203.txt` (M+U modes, PMP)

---

## Roadmap

Komandara is designed as a family of cores with increasing complexity:

| Generation | Key Features | Status |
|---|---|---|
| **K10** | 5-stage in-order, M+U modes, PMP, AXI4-Lite | 🔨 In Progress |
| **K20** | Sv32 MMU + Supervisor Mode (S) → Linux-capable | 📋 Planned |
| **K40** | Dual Core + L1 Cache Coherence (MESI) + Atomics | 📋 Planned |
| **K61** | Out-of-Order Execution + Superscalar | 📋 Planned |

---

## Repository Structure

```
komandara/
├── rtl/
│   ├── k10/                         # K10 CPU + SoC + target + TB RTL
│   └── ip/                          # Reusable IP modules (axi4, axi4lite, common)
├── 3rdParty/
│   └── pulp_riscv_dbg/              # 3rd-party vendored RISC-V debug module RTL
├── sw/k10/                          # Software tests and firmware
├── scripts/                         # Build, setup & verification scripts
├── komandara_*.core                 # FuseSoC core descriptors
├── build.sh                         # Unified build orchestration script
├── spec/                            # RISC-V specification documents
├── tools/                           # Installed tools (gitignored)
└── build/                           # Build artifacts (gitignored)
```

---

## Verification Status

### K10 Core

| Test | Method | Status |
|---|---|---|
| **Smoke Test** (basic arithmetic) | Spike trace comparison | ✅ Pass |
| **Unaligned Memory Access** (19 tests) | Self-checking (LW/LH/LHU/SW/SH at offset +1,+2,+3) | ✅ Pass |
| **Multiply/Divide** (standalone) | Self-checking (MUL/MULH/DIV/REM/DIVU/REMU, div-by-zero, overflow) | ✅ Pass |
| **C Self-Test Suite** (`sw/k10/test/k10_c_selftest.c`) | Self-checking (Arithmetic, Unaligned, IRQ, Traps) | ✅ Pass |
| **RISC-DV Arithmetic** (`k10_arithmetic_basic_test`) | Spike trace comparison (random, 200 instr) | ✅ Pass |
| **RISC-DV Random Mix** (`k10_rand_instr_test`) | Spike trace comparison | ✅ Pass |
| **RISC-DV Jump Stress** (`k10_jump_stress_test`) | Spike trace comparison | ✅ Pass |
| **RISC-DV Loop Stress** (`k10_loop_test`) | Spike trace comparison | ✅ Pass |
| **RISC-DV Random Jump** (`k10_rand_jump_test`) | Spike trace comparison | ✅ Pass |
| **RISC-DV No-Fence Profile** (`k10_no_fence_test`) | Spike trace comparison | ✅ Pass |
| **RISC-DV Illegal Instruction** (`k10_illegal_instr_test`) | Spike trace comparison | ✅ Pass |
| **RISC-DV EBREAK** (`k10_ebreak_test`) | Spike trace comparison | ✅ Pass |
| **RISC-DV EBREAK Debug** (`k10_ebreak_debug_mode_test`) | Spike trace comparison | ✅ Pass |
| **RISC-DV Interrupt** (`k10_full_interrupt_test`) | Spike trace comparison | ✅ Pass |
| **RISC-DV CSR** (`k10_csr_test`) | Spike trace comparison | ✅ Pass |
| **RISC-DV Load/Store** (`k10_unaligned_load_store_test`) | Spike trace comparison | ✅ Pass |
| **RISC-DV AMO** (`k10_amo_test`) | Spike trace comparison | ✅ Pass |
| **RISC-DV PMP** (`k10_pmp_test`) | Spike trace comparison | ✅ Pass |
| **RISC-DV Privileged Mode** (`k10_privileged_mode_rand_test`) | Spike trace comparison | ✅ Pass |
| **RISC-DV Invalid CSR** (`k10_invalid_csr_test`) | Spike trace comparison | ✅ Pass |
| **RISC-DV Performance Counter** (`k10_perf_counter_test`) | Spike trace comparison | ✅ Pass |
| **RISC-DV Fence** (`k10_fence_test`) | Spike trace comparison | ✅ Pass |
| **RISC-DV Callstack Depth** (`k10_callstack_depth_test`) | Spike trace comparison | ✅ Pass |
| **RISC-DV ISA Smoke** (`k10_isa_smoke_test`) | Spike trace comparison | ✅ Pass |
| **RISC-DV Debug Single-Step** (`k10_debug_single_step_test`) | Spike trace comparison | ✅ Pass |
| **RISC-DV Fence Order Smoke** (`k10_fence_order_smoke_test`) | Spike trace comparison | ✅ Pass |
| **RISC-DV LS Hazard Smoke** (`k10_ls_hazard_smoke_test`) | Spike trace comparison | ✅ Pass |

### Bus Infrastructure

All bus modules verified using **Xilinx AXI Verification IP (VIP)** with 0 failures:

- **AXI4-Lite:** Master, Slave, Parametric Crossbar (N×M)
- **AXI4 Full:** Master, Slave, Parametric Crossbar (N×M)
- **Skid Buffers:** Full-throughput, zero-bubble operation
- **Arbiter:** Round-robin and fixed-priority policies

---

## K10 Microarchitecture

```
+--------------------------------------------------------------------------------+
|                                   k10_core                                     |
|                                                                                |
|  +--------+   +--------+   +---------+   +--------+   +-----------+            |
|  | FETCH  |-->| DECODE |-->| EXECUTE |-->| MEMORY |-->| WRITEBACK |            |
|  |k10_    |   |k10_    |   |k10_     |   |k10_    |   |k10_       |            |
|  |fetch   |   |decode  |   |execute  |   |memory  |   |writeback  |            |
|  +---+----+   +---+----+   +----+----+   +---+----+   +-----------+            |
|      |            |             |            |                                 |
|      |   decode side blocks     |            |                                 |
|      |   - compressed decoder   |            |                                 |
|      |   - regfile              |            |                                 |
|      |                          |            |                                 |
|      |              execute side blocks      memory side blocks                |
|      |              - ALU                    - LSU (unaligned split)           |
|      |              - IMM generator          - PMP checks                      |
|      |              - MUL/DIV                                                  |
|      |              - CSR path                                                 |
|      |                                                                         |
|      +------------------ HAZARD UNIT (forwarding/stall/flush) --------------+  |
+--------------------------------------------------------------------------------+
                 | ibus                                   | dbus
                 v                                        v
            +------------+                          +------------+
            | bus2axi4   |                          | bus2axi4   |
            | lite       |                          | lite       |
            +-----+------+                          +-----+------+
                  |                                         |
                  +----------------+   +--------------------+
                                   |   |
                          +--------+---+--------+
                          | AXI4-Lite XBAR (2x2)|
                          +--------+---+--------+
                                   |   |
                           +-------+   +---------+
                           | BRAM  |   | Periph  |
                           |64KB d.|   | Port    |
                           +-------+   +---------+
```

### Key Design Decisions

- **Unaligned Access:** The LSU transparently splits unaligned word/halfword accesses into two consecutive aligned bus operations. No trap handler needed.
- **Multiply:** Single-cycle combinational (synthesis tool handles timing).
- **Divide:** Iterative restoring division (33 cycles). FSM holds result until pipeline consumes it.
- **Forwarding:** Full MEM→EX and WB→EX forwarding, including to MUL/DIV operands and CSR write data.
- **Compressed Instructions:** RV32C instructions expanded to RV32I equivalents in the decode stage.
- **Memory:** BRAM module designed to infer FPGA BRAM. Size configurable via FuseSoC parameter `MEM_SIZE_KB`.

---

## Design Philosophy

### Vibe Coding

This project follows a strict division of labor:

- **Human (System Architect):** Defines the ISA target, pipeline architecture, bus topology, memory map, privilege model, and verification strategy. Writes the rules and constraints. Reviews simulation results. Makes architectural decisions.
- **AI (RTL Engineer):** Implements all SystemVerilog modules, testbenches, scripts, and FuseSoC core files. Debugs simulation failures. Iterates until verification passes.

The human intervenes in the code as little as possible — ideally, **not at all.** The goal is to explore how far AI-assisted hardware design can go when the human focuses purely on architecture and specification.

### RTL Coding Standards

- **ASIC-style:** No FPGA primitives, no `initial` blocks, portable across toolchains
- **Two-segment style** (Pong Chu): Strict separation of combinational (`always_comb`) and sequential (`always_ff`) logic
- **`logic` everywhere:** No `wire` or `reg` — only `logic`
- **Parametric design:** All infrastructure modules are generic and reusable
- **Async active-low reset:** `always_ff @(posedge i_clk or negedge i_rst_n)`

---

## Prerequisites

### System Packages (Ubuntu 22.04+)

```bash
sudo apt-get install -y \
    git make autoconf g++ flex bison ccache \
    libfl-dev libfl2 zlib1g-dev \
    device-tree-compiler libboost-all-dev \
    perl python3 python3-venv \
    numactl curl help2man cmake nodejs npm
```

### Optional (for AXI VIP verification)

- **Vivado 2023.2+** — Required only for Xilinx AXI VIP testbenches

---

## Getting Started

### One-Time Setup

```bash
# 1. Create and activate Python virtual environment
python3 -m venv .venv
source .venv/bin/activate

# 2. Run the tool setup script (builds Verilator, Spike, downloads toolchain, etc.)
./scripts/setup_tools.sh
```

### Daily Workflow

```bash
# Activate venv (Komandara env is auto-loaded)
source .venv/bin/activate

# Now you can use: verilator, spike, riscv32-unknown-elf-gcc, fusesoc
```

### What `setup_tools.sh` Installs

All tools are installed **locally** into the `tools/` directory (gitignored):

| Tool | Purpose | Location |
|---|---|---|
| **Verilator** (v5.028) | RTL simulation & linting | `tools/verilator/` |
| **Spike** | RISC-V ISA golden reference model | `tools/spike/` |
| **RISC-V GNU Toolchain** | Cross-compiler (`riscv32-unknown-elf-gcc`) | `tools/riscv-toolchain/` |
| **RISC-V DV** | Random instruction generator | `tools/riscv-dv/` |
| **FuseSoC** | Build system (via pip) | `.venv/` |

---

## Running Tests

### Smoke Test (Spike Comparison)

```bash
./scripts/run_riscv_dv.sh --asm sw/k10/test/smoke_test.S
```

### Manual Test Runner (CMake)

```bash
./scripts/run_riscv_dv.sh --manuel-test smoke_test
./scripts/run_riscv_dv.sh --manuel-test k10_c_selftest
```

### RISC-DV Random Arithmetic Test

```bash
./scripts/run_riscv_dv.sh --test k10_arithmetic_basic_test --seed 42
```

### Unaligned Memory Access Test (Self-Checking)

```bash
./scripts/run_selfcheck_test.sh sw/k10/test/unaligned_test.S
```

### Standalone Mul/Div Test

```bash
# Build and run from rtl/k10/tb/
fusesoc --cores-root=. run --target=sim --build komandara:core:k10
```

### Genesys2 FPGA Build + Program

```bash
# Ensure Vivado is in your PATH before building
source /path/to/Xilinx/Vivado/<version>/settings64.sh

# Build bitstream
./build.sh genesys2

# Program the board
./build/fpga_run.sh
```

### Genesys2 Netlist Smoke (Real App)

```bash
# Builds a tiny SW app, bakes it into MEM_INIT, then runs:
#  - post-synthesis functional netlist sim
#  - post-implementation timing netlist sim
./scripts/run_fpga_netlist_smoke.sh
```

### Unified Build Script (`build.sh`)

We provide a unified bash script to orchestrate the software CMake cross-compilation and the hardware FuseSoC execution flow automatically.

```bash
# Verilator simulation build
./build.sh sim

# Run the simulation
./build/Vk10
```

```bash
# FPGA synthesis (ensure Vivado is sourced first)
source /path/to/Xilinx/Vivado/<version>/settings64.sh
./build.sh genesys2

# Program the board
./build/fpga_run.sh
```

---

## VSCode Extension: Komandara Wizard

Komandara includes a VSCode extension designed to instantly scaffold an isolated C software project. This eliminates the need to rely on the repository's internal CMake framework when writing test programs or real applications. The extension generated during the `./build.sh` process automatically bundles all the boilerplate you need (such as `k10.h`, `startup.S`, a fully-configured `CMakeLists.txt`, the `riscv32.cmake` cross-compilation toolchain, and even a pre-written `launch.json` OpenOCD target for your specific board).

### Installation and Usage

1. **Build the extension package**:
   Running `./build.sh` (for either `sim` or `genesys2`) automatically packages the extension into the `build/` directory.
2. **Install into VSCode**:
   Open VSCode, go to the Extensions view, click the `...` menu at the top right, and select **Install from VSIX**. Point it to `build/komandara-wizard.vsix`.
3. **Create a new Project**:
   Press `Ctrl+Shift+P` (or `Cmd+Shift+P`) and run **Komandara: Create Project**.
4. **Follow the Prompts**:
   Select your target board (e.g., `Genesys 2` or `Simulation`) and choose an empty directory for your new workspace.
5. **Debug**:
   The generated workspace is fully decoupled from the core repository and ready for Cortex-Debug stepping!

---

## Build System

The project uses **FuseSoC** (CAPI2) for dependency management and build orchestration.

Core files follow the naming convention: `komandara:<lib>:<name>:<version>`

### FuseSoC Parameters

| Parameter | Default | Description |
|---|---|---|
| `MEM_SIZE_KB` | 64 | BRAM size in kilobytes (must be power of 2) |
| `BOOT_ADDR` | 0 | Initial program counter value |
| `MEM_INIT` | "" | Path to hex file for BRAM initialisation |

---

## Contributing

Contributions are highly welcome! Whether you want to improve the verification infrastructure, write new software tests, propose architectural enhancements, or fix bugs, feel free to open issues and pull requests.

When contributing, please ensure that you adhere to the project's SystemVerilog coding standards and verify your changes by running the existing Verilator and RISC-DV test suites.

---

## License

Licensed under the Apache License, Version 2.0. See `LICENSE`.

---

## Acknowledgments

- **RISC-V Foundation** for the open ISA specifications
- **Xilinx/AMD** for the AXI Verification IP used in bus module verification
- AI tooling (including Cursor and LLMs such as ChatGPT and Gemini) for making vibe-coded hardware design possible
