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

// ============================================================================
// K10 — Verilator C++ Testbench Driver
// ============================================================================
// Usage:
//   ./Vk10_tb [+verilator+seed+<N>] [--trace]
//
// The simulation terminates when:
//   1. The SV testbench detects an ECALL/sim_ctrl ($finish), or
//   2. MAX_CYCLES is reached (timeout / fail)
//
// --trace  enables FST waveform dump to k10_sim.fst
// ============================================================================

#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <memory>

#include "Vk10_tb.h"
#include "verilated.h"

#ifdef VM_TRACE_FST
#include "verilated_fst_c.h"
#endif

static constexpr uint64_t MAX_CYCLES = 1'000'000;
static constexpr int      RESET_CYCLES = 5;

int main(int argc, char** argv)
{
    // Verilator context
    const std::unique_ptr<VerilatedContext> ctx{new VerilatedContext};
    ctx->commandArgs(argc, argv);

    // Parse custom args
    bool do_trace = false;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--trace") == 0) do_trace = true;
    }

    // DUT
    const std::unique_ptr<Vk10_tb> top{new Vk10_tb{ctx.get(), "TOP"}};

    // FST trace
#ifdef VM_TRACE_FST
    VerilatedFstC* tfp = nullptr;
    if (do_trace) {
        ctx->traceEverOn(true);
        tfp = new VerilatedFstC;
        top->trace(tfp, 99);
        tfp->open("k10_sim.fst");
        printf("[K10_TB] FST trace enabled: k10_sim.fst\n");
    }
#else
    (void)do_trace;
#endif

    // Initialise signals
    top->i_clk   = 0;
    top->i_rst_n = 0;

    uint64_t cycle = 0;
    int finish_status = 0;

    while (!ctx->gotFinish() && cycle < MAX_CYCLES) {

        // Toggle clock (2 eval calls per cycle)
        top->i_clk = 0;
        top->eval();
#ifdef VM_TRACE_FST
        if (tfp) tfp->dump(ctx->time());
#endif
        ctx->timeInc(5);

        top->i_clk = 1;
        top->eval();
#ifdef VM_TRACE_FST
        if (tfp) tfp->dump(ctx->time());
#endif
        ctx->timeInc(5);

        // Release reset after RESET_CYCLES
        if (cycle == RESET_CYCLES) {
            top->i_rst_n = 1;
        }

        cycle++;
    }

    if (cycle >= MAX_CYCLES && !ctx->gotFinish()) {
        printf("[K10_TB] ERROR: Timeout after %lu cycles\n", cycle);
        finish_status = 1;
    } else {
        printf("[K10_TB] Simulation finished after %lu cycles\n", cycle);
    }

    // Cleanup
    top->final();

#ifdef VM_TRACE_FST
    if (tfp) {
        tfp->close();
        delete tfp;
    }
#endif

    return finish_status;
}
