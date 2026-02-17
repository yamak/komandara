#!/usr/bin/env bash
# Copyright 2025 The Komandara Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

# ============================================================================
# K10 — Self-Checking Test Runner
# ============================================================================
# Runs a hand-written assembly test that is SELF-CHECKING (the test itself
# verifies correct behavior and signals PASS via ECALL or FAIL via EBREAK).
#
# No Spike comparison — the test is verified entirely within the K10 RTL.
#
# Usage:
#   ./scripts/run_selfcheck_test.sh sw/k10/test/unaligned_test.S
#   ./scripts/run_selfcheck_test.sh sw/k10/test/smoke_test.S
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${PROJECT_ROOT}/build/selfcheck"
ISA="rv32imac_zicsr_zifencei"
ABI="ilp32"
BOOT_ADDR=2147483648  # 0x80000000

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <assembly_file.S>"
    exit 1
fi

ASM_FILE="$1"
TEST_NAME="$(basename "${ASM_FILE}" .S)"

# Environment check
for cmd in riscv32-unknown-elf-gcc verilator fusesoc; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: $cmd not found. Run: source scripts/env.sh"
        exit 1
    fi
done

mkdir -p "${OUTPUT_DIR}"

# ---------------------------------------------------------------------------
# Step 1: Compile assembly → ELF → hex
# ---------------------------------------------------------------------------
echo "=== [1/3] Compiling: ${ASM_FILE} ==="
RISCV_DV="${PROJECT_ROOT}/tools/riscv-dv"
ELF_FILE="${OUTPUT_DIR}/${TEST_NAME}.o"

riscv32-unknown-elf-gcc \
    -static -mcmodel=medany \
    -fvisibility=hidden -nostdlib -nostartfiles \
    -march="${ISA}" -mabi="${ABI}" \
    -I"${RISCV_DV}/user_extension" \
    -T"${RISCV_DV}/scripts/link.ld" \
    "${ASM_FILE}" -o "${ELF_FILE}"

echo "  ELF: ${ELF_FILE}"

# Convert to hex
BYTE_HEX="${OUTPUT_DIR}/${TEST_NAME}_byte.hex"
WORD_HEX="${OUTPUT_DIR}/${TEST_NAME}.hex"

riscv32-unknown-elf-objcopy --change-addresses=-0x80000000 -O verilog \
    "${ELF_FILE}" "${BYTE_HEX}"

python3 "${PROJECT_ROOT}/scripts/verilog_byte2word.py" \
    "${BYTE_HEX}" "${WORD_HEX}"

echo "  HEX: ${WORD_HEX}"

# ---------------------------------------------------------------------------
# Step 2: Build Verilator model
# ---------------------------------------------------------------------------
echo ""
echo "=== [2/3] Building Verilator simulation ==="
VERILATOR_BUILD="${OUTPUT_DIR}/verilator_build"
HEX_ABS="$(realpath "${WORD_HEX}")"

pushd "${PROJECT_ROOT}" > /dev/null
rm -rf "${VERILATOR_BUILD}"
fusesoc --cores-root=. run --target=sim --build \
    --build-root="${VERILATOR_BUILD}" \
    komandara:core:k10 \
    --MEM_INIT="${HEX_ABS}" \
    --BOOT_ADDR="${BOOT_ADDR}" \
    2>&1 | tee "${OUTPUT_DIR}/verilator_build.log"
popd > /dev/null

# ---------------------------------------------------------------------------
# Step 3: Run simulation
# ---------------------------------------------------------------------------
echo ""
echo "=== [3/3] Running K10 simulation: ${TEST_NAME} ==="
pushd "${VERILATOR_BUILD}/sim-verilator" > /dev/null

SIM_EXE="./Vk10_tb"
if [[ ! -x "${SIM_EXE}" ]]; then
    echo "ERROR: Verilator executable not found"
    exit 1
fi

SIM_LOG="${OUTPUT_DIR}/${TEST_NAME}_sim.log"
timeout 60 "${SIM_EXE}" 2>&1 | tee "${SIM_LOG}"
SIM_EXIT=${PIPESTATUS[0]}

popd > /dev/null

# ---------------------------------------------------------------------------
# Check result
# ---------------------------------------------------------------------------
echo ""
if grep -q "simulation PASSED" "${SIM_LOG}"; then
    echo "=== ✅ ${TEST_NAME}: ALL TESTS PASSED ==="
    exit 0
elif grep -q "ECALL detected" "${SIM_LOG}" && ! grep -q "ERROR: Timeout" "${SIM_LOG}"; then
    echo "=== ✅ ${TEST_NAME}: ALL TESTS PASSED ==="
    exit 0
elif grep -q "TEST FAILED" "${SIM_LOG}"; then
    echo "=== ❌ ${TEST_NAME}: TEST FAILED ==="
    grep "TEST FAILED" "${SIM_LOG}"
    exit 1
else
    echo "=== ❌ ${TEST_NAME}: TIMEOUT or UNKNOWN RESULT ==="
    exit 1
fi
