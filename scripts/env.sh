#!/usr/bin/env bash
# =============================================================================
# Komandara — Environment Setup
# =============================================================================
# Source this file after activating the Python venv:
#   source .venv/bin/activate
#   source scripts/env.sh
# =============================================================================

# ---------------------------------------------------------------------------
# Resolve project root from this script's location (works with both bash & zsh)
# ---------------------------------------------------------------------------
if [ -n "${ZSH_VERSION:-}" ]; then
    _KOMANDARA_ENV_DIR="${0:A:h}"
elif [ -n "${BASH_SOURCE[0]:-}" ]; then
    _KOMANDARA_ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    _KOMANDARA_ENV_DIR="$(cd "$(dirname "$0")" && pwd)"
fi
export KOMANDARA_ROOT="$(cd "${_KOMANDARA_ENV_DIR}/.." && pwd)"
export KOMANDARA_TOOLS="${KOMANDARA_ROOT}/tools"
unset _KOMANDARA_ENV_DIR

if [[ "${KOMANDARA_ENV_LOADED:-0}" == "1" && "${KOMANDARA_ENV_ROOT:-}" == "${KOMANDARA_ROOT}" ]]; then
    return 0 2>/dev/null || exit 0
fi

# ---------------------------------------------------------------------------
# Tool paths (all relative to KOMANDARA_ROOT)
# ---------------------------------------------------------------------------

# Verilator — do NOT set VERILATOR_ROOT; the installed binary self-locates
export PATH="${KOMANDARA_TOOLS}/verilator/bin:${PATH}"

# Spike
export PATH="${KOMANDARA_TOOLS}/spike/bin:${PATH}"

# RISC-V Toolchain
export RISCV="${KOMANDARA_TOOLS}/riscv-toolchain"
export RISCV_GCC="${RISCV}/bin/riscv32-unknown-elf-gcc"
export RISCV_OBJCOPY="${RISCV}/bin/riscv32-unknown-elf-objcopy"
export RISCV_OBJDUMP="${RISCV}/bin/riscv32-unknown-elf-objdump"
export PATH="${RISCV}/bin:${PATH}"

# RISC-V DV
export RISCV_DV="${KOMANDARA_TOOLS}/riscv-dv"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "[env.sh] Komandara verification environment loaded."
echo "  ROOT      : ${KOMANDARA_ROOT}"
echo "  VERILATOR : $(verilator --version 2>/dev/null || echo 'not found')"
echo "  SPIKE     : $(spike --help 2>&1 | { head -1 || true; } 2>/dev/null)"
echo "  RISCV_GCC : $(${RISCV_GCC} --version 2>/dev/null | { head -1 || true; } 2>/dev/null || echo 'not found')"
echo "  RISCV_DV  : ${RISCV_DV}"

export KOMANDARA_ENV_LOADED=1
export KOMANDARA_ENV_ROOT="${KOMANDARA_ROOT}"
