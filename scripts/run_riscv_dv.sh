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

# Special modes
RUN_ALL=0
RUN_APP=0

# BRAM config
BOOT_ADDR=2147483648  # 0x80000000

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
usage() {
    echo "Usage: $0 [--test <name>] [--asm <file.S>] [--all] [--app] [--iterations <N>] [--seed <N>] [--output <dir>]"
    echo ""
    echo "  --test        RISC-DV test name (default: riscv_arithmetic_basic_test)"
    echo "  --asm         Use a hand-written assembly file instead of RISC-DV"
    echo "  --all         Run all 13 RISC-DV tests sequentially"
    echo "  --app         Build and run the C test application (sw/k10/)"
    echo "  --iterations  Number of test iterations (default: 1)"
    echo "  --seed        Random seed for test generation"
    echo "  --output      Output directory (default: build/riscv_dv)"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --test)       TEST_NAME="$2";   shift 2 ;;
        --asm)        ASM_FILE="$2";    shift 2 ;;
        --all)        RUN_ALL=1;        shift ;;
        --app)        RUN_APP=1;        shift ;;
        --iterations) ITERATIONS="$2";  shift 2 ;;
        --seed)       SEED="$2";        shift 2 ;;
        --output)     OUTPUT_DIR="$2";  shift 2 ;;
        -h|--help)    usage ;;
        *)            echo "Unknown option: $1"; usage ;;
    esac
done

# ---------------------------------------------------------------------------
# --app mode: Build & run C test suite, then exit
# ---------------------------------------------------------------------------
if [[ "${RUN_APP}" -eq 1 ]]; then
    echo "=== Running C Test Application ==="
    APP_DIR="${PROJECT_ROOT}/sw/k10"
    APP_BUILD="${APP_DIR}/build"

    echo "  Building sw/k10 with CMake..."
    cmake -B "${APP_BUILD}" -S "${APP_DIR}" \
        -DCMAKE_TOOLCHAIN_FILE="${APP_DIR}/riscv32.cmake" 2>&1
    cmake --build "${APP_BUILD}" 2>&1

    APP_ELF="${APP_BUILD}/k10_test_suite.elf"
    APP_HEX="${OUTPUT_DIR}/k10_test_suite.hex"
    APP_BYTE_HEX="${OUTPUT_DIR}/k10_test_suite_byte.hex"
    mkdir -p "${OUTPUT_DIR}"

    echo "  Converting ELF → hex..."
    riscv32-unknown-elf-objcopy --change-addresses=-0x80000000 -O verilog \
        "${APP_ELF}" "${APP_BYTE_HEX}"
    python3 "${PROJECT_ROOT}/scripts/verilog_byte2word.py" \
        "${APP_BYTE_HEX}" "${APP_HEX}"

    echo "  Building Verilator model..."
    pushd "${PROJECT_ROOT}" > /dev/null
    fusesoc --cores-root=. run --target=sim --build \
        komandara:core:k10 \
        --MEM_INIT="$(realpath "${APP_HEX}")" \
        --BOOT_ADDR="${BOOT_ADDR}" 2>&1
    popd > /dev/null

    SIM_DIR="${PROJECT_ROOT}/build/komandara_core_k10_0.1.0/sim-verilator"
    echo "  Running simulation..."
    timeout 60 "${SIM_DIR}/Vk10_tb" --trace 2>&1 || true

    if [[ -f "k10_sim.fst" ]]; then
        cp k10_sim.fst "${OUTPUT_DIR}/k10_sim.fst"
        echo "  FST Trace: ${OUTPUT_DIR}/k10_sim.fst"
    fi

    if [[ -f "k10_trace.csv" ]]; then
        cp k10_trace.csv "${OUTPUT_DIR}/k10_test_suite.csv"
        echo "  CSV Trace: ${OUTPUT_DIR}/k10_test_suite.csv"
    fi

    echo "=== C Test Application Complete ==="
    exit 0
fi

# ---------------------------------------------------------------------------
# --all mode: Run all tests from testlist.yaml
# ---------------------------------------------------------------------------
if [[ "${RUN_ALL}" -eq 1 ]]; then
    TESTLIST="${PROJECT_ROOT}/rtl/k10/tb/testlist.yaml"
    ALL_TESTS=$(grep '^- test:' "${TESTLIST}" | awk '{print $3}')

    PASS_COUNT=0
    FAIL_COUNT=0
    FAIL_TESTS=""

    for t in ${ALL_TESTS}; do
        echo ""
        echo "====================================================="
        echo "Running: ${t}"
        echo "====================================================="
        if "$0" --test "${t}" --output "${OUTPUT_DIR}/${t}"; then
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
            FAIL_TESTS="${FAIL_TESTS} ${t}"
        fi
    done

    echo ""
    echo "====================================================="
    echo "=== All Tests Complete ==="
    echo "  PASSED: ${PASS_COUNT}"
    echo "  FAILED: ${FAIL_COUNT}"
    if [[ ${FAIL_COUNT} -gt 0 ]]; then
        echo "  Failed tests:${FAIL_TESTS}"
        exit 1
    fi
    exit 0
fi

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

if [[ -f "k10_sim.fst" ]]; then
    cp k10_sim.fst "${OUTPUT_DIR}/${TEST_NAME}_k10.fst"
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
