// Copyright 2025 The Komandara Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include "Vtb_mul_div.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <cstring>

// MD operation encodings (from komandara_k10_pkg)
enum MdOp {
    MD_MUL    = 0,
    MD_MULH   = 1,
    MD_MULHSU = 2,
    MD_MULHU  = 3,
    MD_DIV    = 4,
    MD_DIVU   = 5,
    MD_REM    = 6,
    MD_REMU   = 7,
};

static Vtb_mul_div* dut;
static uint64_t sim_time = 0;
static int pass_count = 0;
static int fail_count = 0;

static void tick() {
    dut->i_clk = 0;
    dut->eval();
    sim_time++;
    dut->i_clk = 1;
    dut->eval();
    sim_time++;
}

static void reset() {
    dut->i_rst_n = 0;
    dut->i_start = 0;
    dut->i_op    = 0;
    dut->i_a     = 0;
    dut->i_b     = 0;
    for (int i = 0; i < 5; i++) tick();
    dut->i_rst_n = 1;
    tick();
}

// Run a divide/remainder operation, mimicking pipeline behavior:
//   - Hold i_start high during the entire computation
//   - When o_done goes high, capture the result
//   - Then deassert i_start (pipeline advances)
//   - Return the captured result
static uint32_t run_div_op(uint8_t op, uint32_t a, uint32_t b,
                           int* cycles_out = nullptr) {
    dut->i_op    = op;
    dut->i_a     = a;
    dut->i_b     = b;
    dut->i_start = 1;

    int cycles = 0;
    uint32_t result = 0;
    bool captured = false;

    for (int i = 0; i < 200; i++) {
        tick();
        cycles++;

        if (dut->o_done && !captured) {
            result = dut->o_result;
            captured = true;

            // Check: when o_done is high, o_busy should be low
            if (dut->o_busy) {
                printf("  [WARN] o_busy still high when o_done asserted at cycle %d\n", cycles);
            }
            break;
        }
    }

    if (!captured) {
        printf("  [ERROR] Timeout: o_done never asserted after 200 cycles\n");
        fail_count++;
        dut->i_start = 0;
        tick();
        return 0xDEADBEEF;
    }

    // Deassert start (pipeline advances)
    dut->i_start = 0;
    tick();

    if (cycles_out) *cycles_out = cycles;
    return result;
}

// Run a multiply operation (single-cycle)
static uint32_t run_mul_op(uint8_t op, uint32_t a, uint32_t b) {
    dut->i_op    = op;
    dut->i_a     = a;
    dut->i_b     = b;
    dut->i_start = 1;
    tick();

    uint32_t result = dut->o_result;

    if (!dut->o_done) {
        printf("  [ERROR] o_done not asserted for multiply\n");
        fail_count++;
    }

    dut->i_start = 0;
    tick();
    return result;
}

static void check(const char* name, uint32_t got, uint32_t expected) {
    if (got == expected) {
        printf("  [PASS] %-40s got=0x%08x\n", name, got);
        pass_count++;
    } else {
        printf("  [FAIL] %-40s got=0x%08x expected=0x%08x\n", name, got, expected);
        fail_count++;
    }
}

// Compute expected RISC-V results
static uint32_t riscv_div(int32_t a, int32_t b) {
    if (b == 0) return 0xFFFFFFFF;
    if (a == (int32_t)0x80000000 && b == -1) return 0x80000000; // overflow
    return (uint32_t)(a / b);
}

static uint32_t riscv_divu(uint32_t a, uint32_t b) {
    if (b == 0) return 0xFFFFFFFF;
    return a / b;
}

static uint32_t riscv_rem(int32_t a, int32_t b) {
    if (b == 0) return (uint32_t)a;
    if (a == (int32_t)0x80000000 && b == -1) return 0;
    return (uint32_t)(a % b);
}

static uint32_t riscv_remu(uint32_t a, uint32_t b) {
    if (b == 0) return a;
    return a % b;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    dut = new Vtb_mul_div;

    printf("=== k10_mul_div standalone testbench ===\n\n");

    // ----------------------------------------------------------------
    // Test 1: Basic multiply operations
    // ----------------------------------------------------------------
    printf("--- Multiply Tests ---\n");
    reset();

    check("MUL  3 * 7",   run_mul_op(MD_MUL, 3, 7), 21);
    check("MUL  -3 * 7",  run_mul_op(MD_MUL, -3u, 7), (uint32_t)(-21));
    check("MUL  -3 * -7", run_mul_op(MD_MUL, -3u, -7u), 21);

    // ----------------------------------------------------------------
    // Test 2: Basic unsigned division
    // ----------------------------------------------------------------
    printf("\n--- Unsigned Division Tests ---\n");
    reset();

    uint32_t r;
    int cyc;

    r = run_div_op(MD_DIVU, 10, 3, &cyc);
    check("DIVU 10 / 3", r, 3);
    printf("    (took %d cycles)\n", cyc);

    r = run_div_op(MD_REMU, 10, 3, &cyc);
    check("REMU 10 %% 3", r, 1);

    r = run_div_op(MD_DIVU, 100, 10, &cyc);
    check("DIVU 100 / 10", r, 10);

    r = run_div_op(MD_REMU, 100, 10, &cyc);
    check("REMU 100 %% 10", r, 0);

    // ----------------------------------------------------------------
    // Test 3: Signed division
    // ----------------------------------------------------------------
    printf("\n--- Signed Division Tests ---\n");
    reset();

    r = run_div_op(MD_DIV, -10u, 3, &cyc);
    check("DIV  -10 / 3", r, riscv_div(-10, 3));

    r = run_div_op(MD_REM, -10u, 3, &cyc);
    check("REM  -10 %% 3", r, riscv_rem(-10, 3));

    r = run_div_op(MD_DIV, 10, -3u, &cyc);
    check("DIV  10 / -3", r, riscv_div(10, -3));

    r = run_div_op(MD_REM, 10, -3u, &cyc);
    check("REM  10 %% -3", r, riscv_rem(10, -3));

    r = run_div_op(MD_DIV, -10u, -3u, &cyc);
    check("DIV  -10 / -3", r, riscv_div(-10, -3));

    r = run_div_op(MD_REM, -10u, -3u, &cyc);
    check("REM  -10 %% -3", r, riscv_rem(-10, -3));

    // ----------------------------------------------------------------
    // Test 4: Division by zero
    // ----------------------------------------------------------------
    printf("\n--- Division by Zero Tests ---\n");
    reset();

    r = run_div_op(MD_DIVU, 42, 0, &cyc);
    check("DIVU 42 / 0", r, 0xFFFFFFFF);

    r = run_div_op(MD_REMU, 42, 0, &cyc);
    check("REMU 42 %% 0", r, 42);

    r = run_div_op(MD_DIV, -42u, 0, &cyc);
    check("DIV  -42 / 0", r, 0xFFFFFFFF);

    r = run_div_op(MD_REM, -42u, 0, &cyc);
    check("REM  -42 %% 0", r, (uint32_t)-42);

    // ----------------------------------------------------------------
    // Test 5: Overflow (signed min / -1)
    // ----------------------------------------------------------------
    printf("\n--- Overflow Tests ---\n");
    reset();

    r = run_div_op(MD_DIV, 0x80000000, -1u, &cyc);
    check("DIV  INT_MIN / -1", r, 0x80000000);

    r = run_div_op(MD_REM, 0x80000000, -1u, &cyc);
    check("REM  INT_MIN %% -1", r, 0);

    // ----------------------------------------------------------------
    // Test 6: FAILING cases from RISC-DV trace
    // ----------------------------------------------------------------
    printf("\n--- RISC-DV Failing Cases ---\n");
    reset();

    // Case 1: rem t3, s4, a6 — s4=0x0eca293d, a6=0xeca293d0
    r = run_div_op(MD_REM, 0x0eca293d, 0xeca293d0, &cyc);
    check("REM  0x0eca293d %% 0xeca293d0", r,
          riscv_rem((int32_t)0x0eca293d, (int32_t)0xeca293d0));
    printf("    Expected: 0x%08x\n", riscv_rem((int32_t)0x0eca293d, (int32_t)0xeca293d0));

    // Case 2: divu s9, t6, t1 — t6=0xf01b3076, t1=0x69cc592b
    r = run_div_op(MD_DIVU, 0xf01b3076, 0x69cc592b, &cyc);
    check("DIVU 0xf01b3076 / 0x69cc592b", r,
          riscv_divu(0xf01b3076, 0x69cc592b));

    // Case 4: divu s10, s3, s8
    // Need to find operands from trace — use a large/small case
    r = run_div_op(MD_DIVU, 1, 2, &cyc);
    check("DIVU 1 / 2", r, 0);

    r = run_div_op(MD_REMU, 1, 2, &cyc);
    check("REMU 1 %% 2", r, 1);

    // ----------------------------------------------------------------
    // Test 7: Consecutive divisions (pipeline-like: start new div
    //         immediately after previous completes)
    // ----------------------------------------------------------------
    printf("\n--- Consecutive Division Tests ---\n");
    reset();

    r = run_div_op(MD_DIVU, 100, 7, &cyc);
    check("DIVU 100 / 7 (1st)", r, riscv_divu(100, 7));

    r = run_div_op(MD_DIVU, 200, 13, &cyc);
    check("DIVU 200 / 13 (2nd)", r, riscv_divu(200, 13));

    r = run_div_op(MD_REM, 0x12345678, 0x0000ABCD, &cyc);
    check("REM  0x12345678 %% 0xABCD (3rd)", r,
          riscv_rem(0x12345678, 0x0000ABCD));

    // ----------------------------------------------------------------
    // Summary
    // ----------------------------------------------------------------
    printf("\n=== Summary: %d PASSED, %d FAILED ===\n", pass_count, fail_count);

    dut->final();
    delete dut;
    return fail_count > 0 ? 1 : 0;
}
