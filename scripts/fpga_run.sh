#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────
#  Komandara K10 — Program FPGA
#  Usage: ./scripts/fpga_run.sh [optional-bitstream-path]
# ─────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${REPO_ROOT}/build/komandara_core_k10_0.1.0/genesys2_synth-vivado"
BIT_FILE="${1:-${BUILD_DIR}/komandara_core_k10_0.1.0.runs/impl_1/k10_genesys2_top.bit}"

if [[ ! -f "${BIT_FILE}" ]]; then
    echo "✗ Bitstream not found: ${BIT_FILE}" >&2
    echo "  Build first: ./build.sh genesys2" >&2
    exit 1
fi

if ! command -v vivado &>/dev/null; then
    echo "✗ Vivado not found in PATH." >&2
    echo "  Source it first: source /path/to/Xilinx/Vivado/<version>/settings64.sh" >&2
    exit 1
fi

BIT_FILE="$(readlink -f "${BIT_FILE}")"

echo "⚡ Programming ${BIT_FILE} → Genesys2..."
vivado -mode batch -source "${SCRIPT_DIR}/vivado_program_fpga.tcl" -tclargs "${BIT_FILE}"
echo "✓ FPGA programmed successfully."
