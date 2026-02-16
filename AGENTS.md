# AGENTS.md
Guidance for autonomous coding agents working in this repository.

## 1) Project context
- Project: Komandara RISC-V CPU, current active core is K10.
- Primary languages: SystemVerilog, Bash, Python, C++ (Verilator TB driver).
- Build system: FuseSoC with CAPI2 `.core` files.
- Verification flow: Verilator + riscv-dv + Spike trace comparison.

## 2) Environment setup
Run once from repo root:
```bash
python3 -m venv .venv
source .venv/bin/activate
./scripts/setup_tools.sh
source scripts/env.sh
```
Daily shell setup:
```bash
source .venv/bin/activate
source scripts/env.sh
```

## 3) Build/lint/test commands
Core build/lint gate (Verilator `-Wall` via FuseSoC):
```bash
fusesoc --cores-root=. run --target=sim --build komandara:core:k10
```
Build with explicit memory image + boot address:
```bash
fusesoc --cores-root=. run --target=sim --build komandara:core:k10 --MEM_INIT=/abs/path/test.hex --BOOT_ADDR=2147483648
```
Default end-to-end riscv-dv flow (Spike vs RTL compare):
```bash
./scripts/run_riscv_dv.sh
```
Single riscv-dv random test:
```bash
./scripts/run_riscv_dv.sh --test riscv_arithmetic_basic_test --seed 42
```
Single directed assembly test with Spike comparison:
```bash
./scripts/run_riscv_dv.sh --asm sw/k10/smoke_test.S
```
Single self-checking assembly test (no Spike):
```bash
./scripts/run_selfcheck_test.sh sw/k10/unaligned_test.S
```
Alternative self-check run:
```bash
./scripts/run_selfcheck_test.sh sw/k10/smoke_test.S
```
IP-level simulations (Vivado/xsim):
```bash
fusesoc --cores-root=. run --target=sim_slave komandara:ip:axi4lite
fusesoc --cores-root=. run --target=sim_master komandara:ip:axi4lite
fusesoc --cores-root=. run --target=sim_xbar komandara:ip:axi4lite
fusesoc --cores-root=. run --target=sim_slave komandara:ip:axi4
fusesoc --cores-root=. run --target=sim_master komandara:ip:axi4
fusesoc --cores-root=. run --target=sim_xbar komandara:ip:axi4
```

## 4) Single-test cookbook (preferred)
- Directed `.S` test, self-checking only: `./scripts/run_selfcheck_test.sh <path.S>`.
- Directed `.S` test, ISA golden-model compare: `./scripts/run_riscv_dv.sh --asm <path.S>`.
- One riscv-dv random test: `./scripts/run_riscv_dv.sh --test <name> --seed <N>`.
- Output artifacts: `build/selfcheck` and `build/riscv_dv`.

## 5) Code style and engineering conventions

### 5.1 SystemVerilog rules (mandatory)
- IEEE 1800-2017 syntax.
- Use `logic` consistently; avoid new `wire`/`reg`.
- Two-segment style:
  - `always_comb`: next-state and combinational outputs.
  - `always_ff`: registered state updates only.
- In `always_comb`, start with default assignments to avoid latches.
- Use async active-low reset for sequential logic.
- Prefer `typedef enum logic [N:0]` for FSM states.
- Prefer `struct packed` for bus/control bundles.
- Keep shared architectural types/constants in package files.
- Add SVA for critical invariants (one-hot, handshake stability, deadlock guards).

### 5.2 Naming conventions
- Core-specific modules use `k10_` prefix (example: `k10_decode.sv`).
- Shared reusable IP must be generation-agnostic (use `komandara_...`, not `k10_...`).
- Signal naming convention in existing code:
  - `i_` inputs, `o_` outputs
  - `r_` registered/state signals
  - `w_` combinational signals
- Parameters are uppercase (`BOOT_ADDR`, `MEM_SIZE_KB`, `PMP_REGIONS`).

### 5.3 Imports/includes and dependencies
- In SV modules, import package symbols at module header level.
- In C++, include standard headers first, then generated/model headers.
- In Python, keep stdlib imports first; keep scripts dependency-light.
- In FuseSoC `.core` files, preserve explicit file order and `depend:` relationships.

### 5.4 Formatting and scope control
- Match indentation/alignment style of touched files.
- Keep comments concise and technical.
- Keep long port lists and instantiations vertically aligned.
- Avoid reformatting unrelated regions.

### 5.5 Types and interfaces
- Keep explicit widths on buses and packed fields.
- Prefer project typedefs/structs over ad-hoc bit slicing.
- Preserve interface polarity/reset naming used by each module family (`i_rst_n` vs `rst_ni`).
- For Python additions, prefer type hints on public functions.

### 5.6 Error handling and robustness
- Bash scripts should keep `set -euo pipefail`.
- Quote variable expansions in shell scripts.
- Validate required tools with `command -v` and print clear `ERROR:` messages.
- Python scripts should validate args, print stable usage text, and exit non-zero on failures.
- C++ testbench code should keep timeout guards and non-zero failure exits.
- RTL should fail loudly with assertions on impossible states/protocol violations.

### 5.7 Lint/waiver policy
- Prefer fixing root-cause warnings over waivers.
- Keep Verilator waivers in `rtl/k10/tb/komandara.vlt`.
- Avoid inline `verilator lint_off` in RTL unless unavoidable.
- Keep waivers specific with `-file` and `-match`, and document intent.

### 5.8 Architecture guardrails
- This branch is K10-focused; do not implement K20/K40/K61 features unless explicitly requested.
- Do not add custom instructions or custom CSRs.
- Ground-truth specs:
  - `spec/riscv-spec-20191213.txt`
  - `spec/riscv-privileged-20211203.txt`

## 6) Cursor/Copilot rule integration
Cursor rules found in `.cursor/rules/`:
- `project_identity.mdc`
- `systemverilog_asic.mdc`
- `verification_fusesoc.mdc`
Key points enforced by these rule files:
- K10-only scope and strict adherence to `spec/` docs.
- Apache 2.0 copyright header is required at top of new SV-family source files.
- Shared infrastructure naming must remain generation-agnostic.
- FuseSoC core naming should follow `komandara:<lib>:<name>:<ver>`.
- Use strict Verilator linting and prefer waiver files over inline suppression.
- Use Spike as golden reference when debugging ISA behavior.
No `.cursorrules` file was found.
No `.github/copilot-instructions.md` file was found.

## 7) Practical agent workflow
- Before editing, read the relevant `.core` file and adjacent modules.
- Keep changes minimal and local; avoid broad refactors unless requested.
- Validate with the narrowest command first (single test), then broaden if needed.
- In handoff notes, include exact commands run and artifact paths produced.
