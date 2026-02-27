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
#include <cstdint>
#include <memory>

#include "Vk10_tb.h"
#include "verilated.h"

#ifdef VM_TRACE_FST
#include "verilated_fst_c.h"
#endif

static constexpr uint64_t MAX_CYCLES = 1'000'000;
static constexpr int      RESET_CYCLES = 5;

static uint64_t pack_dmi_req(uint32_t data, uint8_t addr, uint8_t op)
{
    uint64_t v = 0;
    v |= static_cast<uint64_t>(op & 0x3u);
    v |= static_cast<uint64_t>(addr & 0x7fu) << 2;
    v |= static_cast<uint64_t>(data) << 9;
    return v;
}

static void unpack_dmi_resp(uint64_t v, uint32_t& data, uint8_t& addr, uint8_t& resp)
{
    resp = static_cast<uint8_t>(v & 0x3u);
    addr = static_cast<uint8_t>((v >> 2) & 0x7fu);
    data = static_cast<uint32_t>((v >> 9) & 0xffff'ffffULL);
}

int main(int argc, char** argv)
{
    // Verilator context
    const std::unique_ptr<VerilatedContext> ctx{new VerilatedContext};
    ctx->commandArgs(argc, argv);

    // Parse custom args
    bool do_trace = false;
    bool run_jtag_dmi = false;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--trace") == 0) do_trace = true;
        if (strcmp(argv[i], "--run-jtag-dmi") == 0) run_jtag_dmi = true;
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
    top->i_jtag_tck = 0;
    top->i_jtag_tms = 1;
    top->i_jtag_trst_n = 1;
    top->i_jtag_tdi = 0;

    auto eval_and_dump = [&](uint64_t step_ps) {
        top->eval();
#ifdef VM_TRACE_FST
        if (tfp) tfp->dump(ctx->time());
#endif
        ctx->timeInc(step_ps);
    };

    auto jtag_tick = [&](int tms, int tdi) -> int {
        top->i_jtag_tms = tms;
        top->i_jtag_tdi = tdi;
        top->i_jtag_tck = 0;
        eval_and_dump(1);
        top->i_jtag_tck = 1;
        eval_and_dump(1);
        return top->o_jtag_tdo & 0x1;
    };

    auto jtag_reset_to_idle = [&]() {
        for (int i = 0; i < 6; ++i) (void)jtag_tick(1, 0);
        (void)jtag_tick(0, 0);
    };

    auto jtag_shift_ir = [&](uint64_t ir, int nbits) {
        (void)jtag_tick(1, 0); // Select-DR
        (void)jtag_tick(1, 0); // Select-IR
        (void)jtag_tick(0, 0); // Capture-IR
        (void)jtag_tick(0, 0); // Shift-IR
        for (int i = 0; i < nbits; ++i) {
            const int tms = (i == nbits - 1) ? 1 : 0;
            const int tdi = (ir >> i) & 1;
            (void)jtag_tick(tms, tdi);
        }
        (void)jtag_tick(1, 0); // Update-IR
        (void)jtag_tick(0, 0); // Run-Test/Idle
    };

    auto jtag_shift_dr = [&](uint64_t dr, int nbits) -> uint64_t {
        uint64_t out = 0;
        (void)jtag_tick(1, 0); // Select-DR
        (void)jtag_tick(0, 0); // Capture-DR
        (void)jtag_tick(0, 0); // Shift-DR
        for (int i = 0; i < nbits; ++i) {
            const int tms = (i == nbits - 1) ? 1 : 0;
            const int tdi = (dr >> i) & 1;
            const int tdo = jtag_tick(tms, tdi);
            out |= (static_cast<uint64_t>(tdo) << i);
        }
        (void)jtag_tick(1, 0); // Update-DR
        (void)jtag_tick(0, 0); // Run-Test/Idle
        return out;
    };

    auto dmi_scan = [&](uint8_t op, uint8_t addr, uint32_t data) -> uint64_t {
        const uint64_t req = pack_dmi_req(data, addr, op);
        return jtag_shift_dr(req, 41);
    };

    auto jtag_idle = [&](int ncycles) {
        for (int i = 0; i < ncycles; ++i) (void)jtag_tick(0, 0);
    };

    bool jtag_script_done = false;

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

        if (run_jtag_dmi && !jtag_script_done && cycle == (RESET_CYCLES + 30)) {
            jtag_reset_to_idle();
            jtag_shift_ir(0x10, 5); // DTMCS
            uint32_t dtmcs = static_cast<uint32_t>(jtag_shift_dr(0, 32));
            std::printf("[K10_TB:JTAG] dtmcs=0x%08x\n", dtmcs);
            (void)jtag_shift_dr(0x00010000u, 32); // dmireset
            jtag_idle(8);
            (void)jtag_shift_dr(0x00000000u, 32);
            jtag_idle(8);

            jtag_shift_ir(0x11, 5); // DMI

            uint32_t data = 0;
            uint8_t addr = 0;
            uint8_t resp = 0;

            auto dmi_exec = [&](uint8_t op, uint8_t a, uint32_t wdata,
                                uint32_t& rdata, uint8_t& raddr, uint8_t& rresp) {
                (void)dmi_scan(op, a, wdata);
                jtag_idle(8);
                for (int k = 0; k < 128; ++k) {
                    const uint64_t raw = dmi_scan(0, 0x00, 0x00000000);
                    jtag_idle(8);
                    unpack_dmi_resp(raw, rdata, raddr, rresp);
                    if ((rresp != 3) && (raddr == a)) break;
                }
            };

            dmi_exec(2, 0x10, 0x00000001, data, addr, resp); // dmactive
            std::printf("[K10_TB:JTAG] wr dmcontrol dmactive resp=%u\n", resp);

            dmi_exec(2, 0x10, 0x80000001, data, addr, resp); // haltreq + dmactive
            std::printf("[K10_TB:JTAG] wr dmcontrol haltreq resp=%u\n", resp);

            dmi_exec(1, 0x11, 0x00000000, data, addr, resp);
            std::printf("[K10_TB:JTAG] dmstatus=0x%08x addr=0x%02x resp=%u\n", data, addr, resp);

            dmi_exec(2, 0x17, 0x00321008, data, addr, resp); // command: read misa
            std::printf("[K10_TB:JTAG] wr command resp=%u\n", resp);

            for (int i = 0; i < 8; ++i) {
                dmi_exec(1, 0x16, 0x00000000, data, addr, resp);
                std::printf("[K10_TB:JTAG] abstractcs[%d]=0x%08x resp=%u\n", i, data, resp);
            }

            dmi_exec(1, 0x04, 0x00000000, data, addr, resp);
            std::printf("[K10_TB:JTAG] data0=0x%08x addr=0x%02x resp=%u\n", data, addr, resp);

            jtag_script_done = true;
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
