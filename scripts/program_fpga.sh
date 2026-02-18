#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

BIT_FILE="${1:-${REPO_ROOT}/build/komandara_core_k10_0.1.0/genesys2_synth-vivado/komandara_core_k10_0.1.0.bit}"

if [[ ! -f "${BIT_FILE}" ]]; then
    echo "ERROR: Bitstream not found: ${BIT_FILE}" >&2
    echo "Build it first with:" >&2
    echo "  source scripts/vivado_env.sh && fusesoc --cores-root=. run --target=genesys2_synth --build komandara:core:k10" >&2
    exit 1
fi

source "${REPO_ROOT}/scripts/vivado_env.sh"

vivado -mode batch -source "${SCRIPT_DIR}/vivado_program_fpga.tcl" -tclargs "${BIT_FILE}"
