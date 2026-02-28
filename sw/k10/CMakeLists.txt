cmake_minimum_required(VERSION 3.15)
project(k10_software C ASM)

option(K10_REAL_HW_LOGS "Route self-test logs to UART instead of sim_ctrl" ON)

if(NOT DEFINED K10_MEMINIT_APP)
    set(K10_MEMINIT_APP "k10_c_selftest")
endif()

add_subdirectory(test)

find_package(Python3 COMPONENTS Interpreter REQUIRED)

if(NOT CMAKE_OBJCOPY)
    find_program(CMAKE_OBJCOPY NAMES riscv32-unknown-elf-objcopy REQUIRED)
endif()

set(K10_MEMINIT_TARGET    "manual_${K10_MEMINIT_APP}")
set(K10_MEMINIT_ELF       "${CMAKE_BINARY_DIR}/${K10_MEMINIT_APP}.elf")
set(K10_MEMINIT_BYTE_HEX  "${CMAKE_BINARY_DIR}/${K10_MEMINIT_APP}.byte.hex")
set(K10_MEMINIT_WORD_HEX  "${CMAKE_BINARY_DIR}/${K10_MEMINIT_APP}.hex")

if(NOT TARGET ${K10_MEMINIT_TARGET})
    message(FATAL_ERROR "K10_MEMINIT_APP='${K10_MEMINIT_APP}' does not map to target '${K10_MEMINIT_TARGET}'.")
endif()

add_custom_command(
    OUTPUT "${K10_MEMINIT_WORD_HEX}"
    COMMAND "${CMAKE_OBJCOPY}" --change-addresses=-0x80000000 -O verilog "${K10_MEMINIT_ELF}" "${K10_MEMINIT_BYTE_HEX}"
    COMMAND "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/../../scripts/verilog_byte2word.py" "${K10_MEMINIT_BYTE_HEX}" "${K10_MEMINIT_WORD_HEX}"
    DEPENDS ${K10_MEMINIT_TARGET} "${CMAKE_SOURCE_DIR}/../../scripts/verilog_byte2word.py"
    COMMENT "Generating ${K10_MEMINIT_APP} MEM_INIT hex"
    VERBATIM
)

add_custom_target(k10_selftest_meminit ALL DEPENDS "${K10_MEMINIT_WORD_HEX}")
