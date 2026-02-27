#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

source "${REPO_ROOT}/scripts/env.sh"

for cmd in riscv32-unknown-elf-gcc riscv32-unknown-elf-objcopy python3 fusesoc cmake; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: Required tool not found: $cmd" >&2
        exit 1
    fi
done

SW_BUILD_DIR="${REPO_ROOT}/build/sw_k10_netlist_smoke"
ELF_FILE="${SW_BUILD_DIR}/netlist_sw_irq_smoke.elf"
BYTE_HEX="${REPO_ROOT}/build/netlist_sw_irq_smoke.byte.hex"
WORD_HEX="${REPO_ROOT}/build/netlist_sw_irq_smoke.hex"
VIVADO_BUILD_DIR="${REPO_ROOT}/build/komandara_core_k10_0.1.0/genesys2_synth-vivado"
XPR_FILE="${VIVADO_BUILD_DIR}/komandara_core_k10_0.1.0.xpr"

echo "=== [1/5] Build netlist smoke app ==="
cmake \
    -S "${REPO_ROOT}/sw/k10" \
    -B "${SW_BUILD_DIR}" \
    -DCMAKE_TOOLCHAIN_FILE="${REPO_ROOT}/sw/k10/riscv32.cmake"

cmake --build "${SW_BUILD_DIR}" --target manual_netlist_sw_irq_smoke -j "$(nproc)"

if [[ ! -f "${ELF_FILE}" ]]; then
    echo "ERROR: ELF not found: ${ELF_FILE}" >&2
    exit 1
fi

echo "=== [2/5] Convert ELF to MEM_INIT hex ==="
riscv32-unknown-elf-objcopy --change-addresses=-0x80000000 -O verilog \
    "${ELF_FILE}" "${BYTE_HEX}"

python3 "${REPO_ROOT}/scripts/verilog_byte2word.py" "${BYTE_HEX}" "${WORD_HEX}"

echo "=== [3/5] Build FPGA project with smoke app ==="
source "${REPO_ROOT}/scripts/vivado_env.sh"

if ! command -v vivado >/dev/null 2>&1; then
    echo "ERROR: Required tool not found: vivado" >&2
    exit 1
fi

fusesoc --cores-root="${REPO_ROOT}" run --target=genesys2_synth --build komandara:core:k10 \
    --MEM_INIT="${WORD_HEX}" \
    --BOOT_ADDR=2147483648

if [[ ! -f "${XPR_FILE}" ]]; then
    echo "ERROR: Vivado project not found: ${XPR_FILE}" >&2
    exit 1
fi

echo "=== [4/5] Post-synthesis functional netlist sim ==="
echo "=== [5/5] Post-implementation timing netlist sim ==="
vivado -mode batch -source "${REPO_ROOT}/scripts/vivado_netlist_sims.tcl" -tclargs "${XPR_FILE}"

echo "DONE: Netlist smoke app passed in post-synth and post-impl timing sims"
