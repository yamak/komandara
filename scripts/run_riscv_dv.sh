#!/usr/bin/env bash
# Copyright 2025 The Komandara Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

# ============================================================================
# K10 — End-to-End RISC-DV Verification Flow
# ============================================================================
# Runs the complete verification pipeline:
#
#   1. Generate random test program with RISC-DV (or use a hand-written .S)
#   2. Compile assembly → ELF → hex
#   3. Run Spike ISS with --log-commits → convert to CSV
#   4. Build & run K10 Verilator simulation → CSV
#   5. Compare K10 trace CSV vs Spike trace CSV
#
# Usage:
#   ./scripts/run_riscv_dv.sh                                  # default: riscv_arithmetic_basic_test
#   ./scripts/run_riscv_dv.sh --test riscv_arithmetic_basic_test
#   ./scripts/run_riscv_dv.sh --asm sw/k10/smoke_test.S        # hand-written test
#
# Prerequisites:
#   source scripts/env.sh
# ============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${PROJECT_ROOT}/build/riscv_dv"
RISCV_DV="${PROJECT_ROOT}/tools/riscv-dv"
ISA="rv32imac_zicsr_zifencei"
ABI="ilp32"
MAX_CYCLES=1000000

# RISC-DV mode (default)
TEST_NAME="riscv_arithmetic_basic_test"
ITERATIONS=1
SEED=""

# Manual mode
ASM_FILE=""

# BRAM config
BOOT_ADDR=2147483648  # 0x80000000

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
usage() {
    echo "Usage: $0 [--test <name>] [--asm <file.S>] [--iterations <N>] [--seed <N>] [--output <dir>]"
    echo ""
    echo "  --test        RISC-DV test name (default: riscv_arithmetic_basic_test)"
    echo "  --asm         Use a hand-written assembly file instead of RISC-DV"
    echo "  --iterations  Number of test iterations (default: 1)"
    echo "  --seed        Random seed for test generation"
    echo "  --output      Output directory (default: build/riscv_dv)"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --test)       TEST_NAME="$2";   shift 2 ;;
        --asm)        ASM_FILE="$2";    shift 2 ;;
        --iterations) ITERATIONS="$2";  shift 2 ;;
        --seed)       SEED="$2";        shift 2 ;;
        --output)     OUTPUT_DIR="$2";  shift 2 ;;
        -h|--help)    usage ;;
        *)            echo "Unknown option: $1"; usage ;;
    esac
done

# ---------------------------------------------------------------------------
# Environment check
# ---------------------------------------------------------------------------
for cmd in riscv32-unknown-elf-gcc spike verilator fusesoc python3; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: $cmd not found. Run: source scripts/env.sh"
        exit 1
    fi
done

mkdir -p "${OUTPUT_DIR}"

# Set PYTHONPATH for RISC-DV pygen
export PYTHONPATH="${RISCV_DV}/pygen:${PYTHONPATH:-}"

# ---------------------------------------------------------------------------
# Step 1: Generate or compile test program
# ---------------------------------------------------------------------------
ELF_FILE="${OUTPUT_DIR}/${TEST_NAME}.o"

if [[ -n "${ASM_FILE}" ]]; then
    # Manual assembly mode
    TEST_NAME="$(basename "${ASM_FILE}" .S)"
    ELF_FILE="${OUTPUT_DIR}/${TEST_NAME}.o"

    echo "=== [1/5] Compiling assembly: ${ASM_FILE} ==="
    riscv32-unknown-elf-gcc \
        -static -mcmodel=medany \
        -fvisibility=hidden -nostdlib -nostartfiles \
        -march="${ISA}" -mabi="${ABI}" \
        -I"${RISCV_DV}/user_extension" \
        -T"${RISCV_DV}/scripts/link.ld" \
        "${ASM_FILE}" -o "${ELF_FILE}"
else
    # RISC-DV random generation mode
    echo "=== [1/5] Generating test with RISC-DV: ${TEST_NAME} ==="

    SEED_OPT=""
    if [[ -n "${SEED}" ]]; then
        SEED_OPT="--seed ${SEED}"
    fi

    python3 "${RISCV_DV}/run.py" \
        --custom_target "${PROJECT_ROOT}/rtl/k10/tb" \
        --test "${TEST_NAME}" \
        --steps gen,gcc_compile \
        --iterations "${ITERATIONS}" \
        --simulator pyflow \
        --isa "${ISA}" \
        --mabi "${ABI}" \
        -o "${OUTPUT_DIR}" \
        ${SEED_OPT} \
        2>&1 | tee "${OUTPUT_DIR}/riscv_dv_gen.log"

    # RISC-DV places compiled ELF in asm_test/
    ELF_FILE="$(find "${OUTPUT_DIR}/asm_test" -name "${TEST_NAME}*.o" -type f | head -1)"
    if [[ -z "${ELF_FILE}" || ! -f "${ELF_FILE}" ]]; then
        echo "ERROR: RISC-DV did not produce an ELF file"
        exit 1
    fi
fi

echo "  ELF: ${ELF_FILE}"

# ---------------------------------------------------------------------------
# Step 2: Create hex file for BRAM
# ---------------------------------------------------------------------------
echo ""
echo "=== [2/5] Converting ELF → hex for Verilator ==="

# objcopy produces byte-addressed verilog hex;
# strip the 0x80000000 base and convert to 32-bit words for $readmemh
BYTE_HEX="${OUTPUT_DIR}/${TEST_NAME}_byte.hex"
WORD_HEX="${OUTPUT_DIR}/${TEST_NAME}.hex"

riscv32-unknown-elf-objcopy --change-addresses=-0x80000000 -O verilog \
    "${ELF_FILE}" "${BYTE_HEX}"

python3 "${PROJECT_ROOT}/scripts/verilog_byte2word.py" \
    "${BYTE_HEX}" "${WORD_HEX}"

echo "  HEX: ${WORD_HEX}"

# ---------------------------------------------------------------------------
# Step 3: Run Spike simulation → CSV
# ---------------------------------------------------------------------------
echo ""
echo "=== [3/5] Running Spike ISS simulation ==="
SPIKE_LOG="${OUTPUT_DIR}/${TEST_NAME}_spike.log"
SPIKE_CSV="${OUTPUT_DIR}/${TEST_NAME}_spike.csv"

timeout 30 spike --isa="${ISA}" -l --log-commits "${ELF_FILE}" \
    2>"${SPIKE_LOG}" || true

echo "  Spike log: ${SPIKE_LOG} ($(wc -l < "${SPIKE_LOG}") lines)"

python3 "${RISCV_DV}/scripts/spike_log_to_trace_csv.py" \
    --log "${SPIKE_LOG}" --csv "${SPIKE_CSV}"

echo "  Spike CSV: ${SPIKE_CSV} ($(wc -l < "${SPIKE_CSV}") lines)"

# ---------------------------------------------------------------------------
# Step 4: Build & run K10 Verilator simulation → CSV
# ---------------------------------------------------------------------------
echo ""
echo "=== [4/5] Building & running K10 Verilator simulation ==="

VERILATOR_BUILD="${OUTPUT_DIR}/verilator_build"
K10_CSV="${OUTPUT_DIR}/${TEST_NAME}_k10.csv"

HEX_ABS="$(realpath "${WORD_HEX}")"

# Build with FuseSoC
pushd "${PROJECT_ROOT}" > /dev/null

rm -rf "${VERILATOR_BUILD}"
fusesoc --cores-root=. run --target=sim --build \
    --build-root="${VERILATOR_BUILD}" \
    komandara:core:k10 \
    --MEM_INIT="${HEX_ABS}" \
    --BOOT_ADDR="${BOOT_ADDR}" \
    2>&1 | tee "${OUTPUT_DIR}/verilator_build.log"

popd > /dev/null

# Run simulation
echo "  Running simulation..."
pushd "${VERILATOR_BUILD}/sim-verilator" > /dev/null

SIM_EXE="./Vk10_tb"
if [[ ! -x "${SIM_EXE}" ]]; then
    echo "ERROR: Verilator executable Vk10_tb not found"
    exit 1
fi

timeout 60 "${SIM_EXE}" 2>&1 | tee "${OUTPUT_DIR}/k10_sim.log"

if [[ -f "k10_trace.csv" ]]; then
    cp k10_trace.csv "${K10_CSV}"
else
    echo "ERROR: k10_trace.csv not generated"
    exit 1
fi

popd > /dev/null

echo "  K10 CSV: ${K10_CSV} ($(wc -l < "${K10_CSV}") lines)"

# ---------------------------------------------------------------------------
# Step 5: Compare traces
# ---------------------------------------------------------------------------
echo ""
echo "=== [5/5] Comparing traces: Spike vs K10 ==="
COMPARE_LOG="${OUTPUT_DIR}/${TEST_NAME}_compare.log"

python3 "${RISCV_DV}/scripts/instr_trace_compare.py" \
    --csv_file_1 "${SPIKE_CSV}" --csv_file_2 "${K10_CSV}" \
    --csv_name_1 "spike" --csv_name_2 "k10" \
    --log "${COMPARE_LOG}" \
    2>&1 | tee -a "${COMPARE_LOG}"

echo ""
echo "=== Results ==="
echo "  Compare log: ${COMPARE_LOG}"

if grep -q "PASSED" "${COMPARE_LOG}"; then
    echo "  ✅ PASSED: Spike and K10 traces match"
    exit 0
else
    echo "  ❌ FAILED: Trace mismatch detected"
    echo "  Check ${COMPARE_LOG} for details"
    exit 1
fi
