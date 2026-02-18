cmake_minimum_required(VERSION 3.15)
project(k10_software C ASM)

option(K10_REAL_HW_LOGS "Route self-test logs to UART instead of sim_ctrl" OFF)

add_subdirectory(test)

find_package(Python3 COMPONENTS Interpreter REQUIRED)

if(NOT CMAKE_OBJCOPY)
    find_program(CMAKE_OBJCOPY NAMES riscv32-unknown-elf-objcopy REQUIRED)
endif()

set(K10_SELFTEST_ELF      "${CMAKE_BINARY_DIR}/k10_c_selftest.elf")
set(K10_SELFTEST_BYTE_HEX "${CMAKE_BINARY_DIR}/k10_c_selftest.byte.hex")
set(K10_SELFTEST_WORD_HEX "${CMAKE_BINARY_DIR}/k10_c_selftest.hex")

add_custom_command(
    OUTPUT "${K10_SELFTEST_WORD_HEX}"
    COMMAND "${CMAKE_OBJCOPY}" --change-addresses=-0x80000000 -O verilog "${K10_SELFTEST_ELF}" "${K10_SELFTEST_BYTE_HEX}"
    COMMAND "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/scripts/verilog_byte2word.py" "${K10_SELFTEST_BYTE_HEX}" "${K10_SELFTEST_WORD_HEX}"
    DEPENDS manual_k10_c_selftest "${CMAKE_SOURCE_DIR}/scripts/verilog_byte2word.py"
    COMMENT "Generating k10_c_selftest MEM_INIT hex"
    VERBATIM
)

add_custom_target(k10_selftest_meminit ALL DEPENDS "${K10_SELFTEST_WORD_HEX}")
