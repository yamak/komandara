#!/usr/bin/env python3
# Copyright 2026 The Komandara Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

from __future__ import annotations

import sys
from pathlib import Path


def replace_all(path: Path, replacements: list[tuple[str, str]]) -> None:
    text = path.read_text(encoding="utf-8")
    updated = text
    for old, new in replacements:
        if old in updated:
            updated = updated.replace(old, new)
    if updated != text:
        path.write_text(updated, encoding="utf-8")


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: patch_riscv_dv.py <riscv_dv_root>")
        return 1

    root = Path(sys.argv[1]).resolve()

    replace_all(
        root / "pygen/pygen_src/riscv_asm_program_gen.py",
        [
            ("self.callstack_gen.init(num_sub_program + 1)",
             "callstack_gen.init(num_sub_program + 1)"),
            ("for j in range(len(callstack_gen.program_h.sub_program_id)):",
             "for j in range(len(callstack_gen.program_h[i].sub_program_id)):"),
            ("pid = callstack_gen.program_id[i].sub_program_id[j] - 1",
             "pid = callstack_gen.program_h[i].sub_program_id[j] - 1"),
            ("self.main_program[i].insert_jump_instr(sub_program_name[pid], idx)",
             "main_program.insert_jump_instr(sub_program_name[pid], idx)"),
            ("self.sub_program[i - 1].insert_jump_instr(sub_program_name[pid], idx)",
             "sub_program.insert_jump_instr(sub_program_name[pid], idx)"),
            ("sub_program[i - 1].insert_jump_instr(sub_program_name[pid], idx)",
             "sub_program.insert_jump_instr(sub_program_name[pid], idx)"),
            (
                "            if callstack_gen.randomize():\n",
                "            callstack_ok = False\n"
                "            try:\n"
                "                callstack_ok = bool(callstack_gen.randomize())\n"
                "            except Exception:\n"
                "                callstack_ok = False\n"
                "            if callstack_ok:\n",
            ),
            (
                "            else:\n"
                "                logging.critical(\"Failed to generate callstack\")\n"
                "                sys.exit(1)\n",
                "            else:\n"
                "                logging.warning(\"Callstack randomization failed; skip jump insertion\")\n",
            ),
            (
                "            else:\n"
                "                logging.warning(\"Callstack randomization failed; using linear fallback\")\n"
                "                idx = 0\n"
                "                if len(sub_program_name) > 0:\n"
                "                    main_program.insert_jump_instr(sub_program_name[0], 1)\n"
                "                for i in range(len(sub_program_name) - 1):\n"
                "                    idx += 1\n"
                "                    sub_program[i].insert_jump_instr(sub_program_name[i + 1], idx)\n",
                "            else:\n"
                "                logging.warning(\"Callstack randomization failed; skip jump insertion\")\n",
            ),
        ],
    )

    replace_all(
        root / "pygen/pygen_src/riscv_instr_sequence.py",
        [
            ("def insert_jump_instr(self):", "def insert_jump_instr(self, *args, **kwargs):"),
            ("routine_str = prefix + \"addi x{} x{} {}\".format(ra.get_val(), cfg.ra, rand_lsb)",
             "routine_str = prefix + \"addi x{}, x{}, {}\".format(ra.get_val(), cfg.ra, rand_lsb)"),
            ("routine_str = prefix + \"jalr x{} x{} 0\".format(ra.get_val(), ra.get_val())",
             "routine_str = prefix + \"jalr x{}, x{}, 0\".format(ra.get_val(), ra.get_val())"),
            ("i = random.randrange(0, len(jump_instr) - 1)",
             "i = random.randrange(0, len(jump_instr))"),
        ],
    )

    replace_all(
        root / "pygen/pygen_src/riscv_callstack_gen.py",
        [("riscv_program(\"program_{}\".format(i))", "riscv_program()")],
    )

    replace_all(
        root / "pygen/pygen_src/riscv_amo_instr_lib.py",
        [
            ("self.avail_regs = vsc.randsz_list_t(vsc.enum_t(riscv_reg_t))",
             "self.avail_regs = []"),
            ("self.data_page_id = random.randrange(0, max_data_page_id - 1)",
             "if max_data_page_id <= 1:\n"
             "            self.data_page_id = 0\n"
             "        else:\n"
             "            self.data_page_id = random.randrange(0, max_data_page_id)"),
            ("self.reserved_rd.append(self.rs1_reg)",
             "for i in range(len(self.rs1_reg)):\n"
             "            self.reserved_rd.append(self.rs1_reg[i])"),
        ],
    )

    replace_all(
        root / "pygen/pygen_src/isa/riscv_instr.py",
        [
            ("cls.basic_instr.append(\"EBREAK\")",
             "cls.basic_instr.append(riscv_instr_name_t.EBREAK)"),
            ("cls.basic_instr.append(\"C_EBREAK\")",
             "cls.basic_instr.append(riscv_instr_name_t.C_EBREAK)"),
            ("cls.basic_instr.append(cls.instr_category[\"SYNCH\"])",
             "cls.basic_instr.extend(cls.instr_category[\"SYNCH\"])"),
            ("idx = random.randrange(0, len(allowed_instr) - 1)",
             "idx = random.randrange(0, len(allowed_instr))"),
            ("idx = random.randrange(0, len(cls.instr_names) - 1)",
             "idx = random.randrange(0, len(cls.instr_names))"),
            ("cls.idx = random.randrange(0, len(load_store_instr) - 1)",
             "cls.idx = random.randrange(0, len(load_store_instr))"),
        ],
    )

    replace_all(
        root / "pygen/pygen_src/test/riscv_rand_instr_test.py",
        [
            ("        cfg.instr_cnt = 10000\n        cfg.num_of_sub_program = 5\n", ""),
            (
                "    def apply_directed_instr(self):\n"
                "        # Mix below directed instruction streams with the random instructions\n"
                "        self.asm.add_directed_instr_stream(\"riscv_load_store_rand_instr_stream\", 4)\n"
                "        # self.asm.add_directed_instr_stream(\"riscv_loop_instr\", 3)\n"
                "        self.asm.add_directed_instr_stream(\"riscv_jal_instr\", 4)\n"
                "        # self.asm.add_directed_instr_stream(\"riscv_hazard_instr_stream\", 4)\n"
                "        self.asm.add_directed_instr_stream(\"riscv_load_store_hazard_instr_stream\", 4)\n"
                "        # self.asm.add_directed_instr_stream(\"riscv_multi_page_load_store_instr_stream\", 4)\n"
                "        # self.asm.add_directed_instr_stream(\"riscv_mem_region_stress_test\", 4)\n",
                "    def apply_directed_instr(self):\n"
                "        # Directed streams are configured from testlist gen_opts.\n"
                "        pass\n",
            ),
        ],
    )

    replace_all(
        root / "pygen/pygen_src/target/rv32imc/riscv_core_setting.py",
        [
            (
                "supported_privileged_mode = [privileged_mode_t.MACHINE_MODE]",
                "supported_privileged_mode = [privileged_mode_t.MACHINE_MODE,\n"
                "                             privileged_mode_t.USER_MODE]",
            ),
            (
                "supported_isa = [riscv_instr_group_t.RV32I, riscv_instr_group_t.RV32M, riscv_instr_group_t.RV32C]",
                "supported_isa = [riscv_instr_group_t.RV32I,\n"
                "                 riscv_instr_group_t.RV32M,\n"
                "                 riscv_instr_group_t.RV32A,\n"
                "                 riscv_instr_group_t.RV32C]",
            ),
            ("support_pmp = 0", "support_pmp = 1"),
            ("support_debug_mode = 0", "support_debug_mode = 1"),
            (
                "                   privileged_reg_t.MIP  # Machine interrupt pending\n"
                "                   ]",
                "                   privileged_reg_t.MIP,  # Machine interrupt pending\n"
                "                   privileged_reg_t.MCYCLE,\n"
                "                   privileged_reg_t.MCYCLEH,\n"
                "                   privileged_reg_t.MINSTRET,\n"
                "                   privileged_reg_t.MINSTRETH\n"
                "                   ]",
            ),
        ],
    )

    print(f"Patched riscv-dv tree: {root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
