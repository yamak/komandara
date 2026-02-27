# AGENTS.md
Guidance for coding agents working in this repository.

## 1) Project context
- Project: Komandara RISC-V CPU platform.
- Current scope: K10 core/SoC bring-up and verification.
- Primary languages: SystemVerilog, Bash, Python, C/C++, Tcl.
- Build system: FuseSoC CAPI2 `.core` + CMake helper scripts.
- Reference model flow: Spike compare via `scripts/run_riscv_dv.sh`.

## 2) Environment setup
Run once:
```bash
python3 -m venv .venv
source .venv/bin/activate
./scripts/setup_tools.sh
```
Daily setup:
```bash
source .venv/bin/activate
```
For Vivado flows:
```bash
source scripts/vivado_env.sh
```

## 3) Build / lint / test commands
Core Verilator build/lint gate:
```bash
fusesoc --cores-root=. run --target=sim --build komandara:core:k10
```
Build with explicit memory image + boot address:
```bash
fusesoc --cores-root=. run --target=sim --build komandara:core:k10 --MEM_INIT=/abs/path/test.hex --BOOT_ADDR=2147483648
```
Full riscv-dv flow (RTL vs Spike):
```bash
./scripts/run_riscv_dv.sh
```
Single random test (preferred first repro):
```bash
./scripts/run_riscv_dv.sh --test k10_arithmetic_basic_test --seed 42
```
Single directed asm test with Spike compare:
```bash
./scripts/run_riscv_dv.sh --asm sw/k10/test/smoke_test.S
```
Single manual C/C test target:
```bash
./scripts/run_riscv_dv.sh --manuel-test smoke_test
./scripts/run_riscv_dv.sh --manuel-test k10_c_selftest
```
Note: `--manuel-test` spelling is intentional in this repo.
Single self-check asm test (no Spike):
```bash
./scripts/run_selfcheck_test.sh sw/k10/test/unaligned_test.S
```
IP-level xsim tests:
```bash
fusesoc --cores-root=. run --target=sim_slave komandara:ip:axi4lite
fusesoc --cores-root=. run --target=sim_master komandara:ip:axi4lite
fusesoc --cores-root=. run --target=sim_xbar komandara:ip:axi4lite
fusesoc --cores-root=. run --target=sim_slave komandara:ip:axi4
fusesoc --cores-root=. run --target=sim_master komandara:ip:axi4
fusesoc --cores-root=. run --target=sim_xbar komandara:ip:axi4
```
Genesys2 synth/program:
```bash
source scripts/vivado_env.sh && fusesoc --cores-root=. run --target=genesys2_synth --build komandara:core:k10
source scripts/vivado_env.sh && ./scripts/program_fpga.sh
```
Hardware debug helpers (ILA/OpenOCD):
```bash
source scripts/vivado_env.sh && vivado -mode batch -source scripts/genesys2_ila_build.tcl
source scripts/vivado_env.sh && vivado -mode batch -source scripts/ila_arm.tcl
openocd -f scripts/k10-genesys2-openocd.tcl
source scripts/vivado_env.sh && vivado -mode batch -source scripts/ila_upload.tcl
```

## 4) Single-test cookbook (agent default)
- Start with one deterministic test before full regressions.
- For ISA issues: run one `--test` with fixed `--seed`.
- For directed behavior: run one `--asm` case.
- For quick smoke on local edits: `run_selfcheck_test.sh` first.
- Expand to full `run_riscv_dv.sh` only after single-test pass.
- Artifacts usually appear in `build/riscv_dv` and `build/selfcheck`.

## 5) Code style and conventions

### 5.1 SystemVerilog
- Use IEEE 1800-2017 syntax.
- Prefer `logic`; avoid new `wire/reg` split style.
- Use two-process FSM style (`always_comb` + `always_ff`).
- Provide default assignments in combinational blocks.
- Keep reset polarity/style consistent with surrounding module family.
- Prefer `typedef enum logic [...]` for state machines.
- Prefer packed structs/types from package files for shared interfaces.

### 5.2 Naming
- K10-specific modules/files use `k10_` prefix.
- Shared reusable IP remains generation-agnostic (`komandara_...`).
- Signal prefixes:
  - `i_` input
  - `o_` output
  - `r_` registered/state
  - `w_` combinational/intermediate
- Parameters/constants: uppercase snake case.

### 5.3 Imports, ordering, dependencies
- SV package imports near module header.
- C/C++ includes: stdlib first, project/model headers second.
- Python imports: stdlib, third-party, local.
- Preserve explicit file order and `depend:` structure in `.core` files.

### 5.4 Formatting/edit hygiene
- Match existing style in touched files.
- Keep edits minimal and localized.
- Do not reformat unrelated regions.
- Keep comments concise and technical.

### 5.5 Types, widths, interfaces
- Keep explicit bit widths for buses and packed fields.
- Reuse existing typedefs rather than ad-hoc slicing.
- Respect existing reset naming (`i_rst_n`, `rst_ni`, etc.).
- Prefer Python type hints on public helper functions.

### 5.6 Error handling
- Bash scripts: keep `set -euo pipefail`.
- Validate tool dependencies with `command -v`.
- Print clear `ERROR:` messages and fail non-zero.
- Python CLI scripts should validate args and fail loudly.
- Testbench code should preserve timeout guards and non-zero failure exits.
- RTL should assert impossible/protocol-invalid states where practical.

### 5.7 Lint and waivers
- Fix root causes before adding waivers.
- Keep Verilator waivers in `rtl/k10/tb/komandara.vlt` when possible.
- Avoid broad/global suppressions.
- Keep each waiver narrow and documented.

### 5.8 Scope guardrails
- Stay within K10 scope unless explicitly asked otherwise.
- Do not add custom ISA instructions/CSRs unless requested.
- Prefer spec-conformant behavior over quick hacks.
- Spec anchors:
  - `spec/riscv-spec-20191213.txt`
  - `spec/riscv-privileged-20211203.txt`

## 6) Cursor/Copilot rules integration
Detected Cursor rules in `.cursor/rules/`:
- `project_identity.mdc`
- `systemverilog_asic.mdc`
- `verification_fusesoc.mdc`
Key enforced points:
- K10-focused development and strict spec alignment.
- Apache-2.0 header on new SV-family source files.
- Shared infrastructure naming stays generation-agnostic.
- FuseSoC core naming follows `komandara:<lib>:<name>:<version>`.
- Strict Verilator posture; prefer waiver-file management.
- Use Spike as golden reference for ISA mismatches.
No `.cursorrules` file found.
No `.github/copilot-instructions.md` file found.

## 7) Recommended agent workflow
- Read related `.core` files before changing connectivity.
- Reproduce with narrow test first, then broaden.
- Avoid OpenOCD vs Vivado hw_server contention (one owner of FTDI at a time).
- Report exact commands run and artifact paths in handoff notes.
- Prefer smallest safe change and iterative verification.
