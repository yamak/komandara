cmake_minimum_required(VERSION 3.15)
project(k10_test_suite C ASM)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Toolchain must be specified via -DCMAKE_TOOLCHAIN_FILE=riscv32.cmake

# Compiler flags
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -march=rv32imac_zicsr -mabi=ilp32 -Os -g")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -nostdlib -ffreestanding -fno-builtin")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wall -Wextra")

set(CMAKE_ASM_FLAGS "${CMAKE_C_FLAGS}")

# Linker flags
set(LINKER_SCRIPT ${CMAKE_CURRENT_SOURCE_DIR}/k10_link.ld)
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -T ${LINKER_SCRIPT} -nostartfiles -static -Wl,--gc-sections")

# Include directories
include_directories(include)

# Sources
set(SOURCES
    startup.S
    tests/k10_test_suite.c
)

# Build ELF
add_executable(k10_test_suite.elf ${SOURCES})

# Generate binary and disassembly
add_custom_command(TARGET k10_test_suite.elf POST_BUILD
    COMMAND ${CMAKE_OBJCOPY} -O binary k10_test_suite.elf k10_test_suite.bin
    COMMAND ${CMAKE_OBJDUMP} -d -S k10_test_suite.elf > k10_test_suite.dis
    COMMENT "Generating binary and disassembly"
)
