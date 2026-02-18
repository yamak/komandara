cmake_minimum_required(VERSION 3.15)
project(k10_manual_tests C ASM)
include(CMakeParseArguments)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

option(K10_REAL_HW_LOGS "Route self-test logs to UART instead of sim_ctrl" OFF)

set(LINKER_SCRIPT "${CMAKE_CURRENT_LIST_DIR}/../k10_link.ld")
set(COMMON_FLAGS
    -march=rv32imac_zicsr
    -mabi=ilp32
    -Os
    -g
    -nostdlib
    -ffreestanding
    -fno-builtin
    -Wall
    -Wextra)

include_directories("${CMAKE_CURRENT_LIST_DIR}/include")

function(add_k10_manual_target test_name)
    set(options)
    set(oneValueArgs TYPE SRC)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "" ${ARGN})

    set(target_name "manual_${test_name}")

    if(ARG_TYPE STREQUAL "c")
        add_executable("${target_name}" "${CMAKE_CURRENT_LIST_DIR}/../startup.S" "${ARG_SRC}")
        if(K10_REAL_HW_LOGS)
            target_compile_definitions("${target_name}" PRIVATE K10_REAL_HW=1)
        endif()
    else()
        add_executable("${target_name}" "${ARG_SRC}")
    endif()

    target_compile_options("${target_name}" PRIVATE ${COMMON_FLAGS})
    target_link_options("${target_name}" PRIVATE
        -T "${LINKER_SCRIPT}"
        -nostartfiles
        -static
        -Wl,--gc-sections)

    set_target_properties("${target_name}" PROPERTIES
        OUTPUT_NAME "${test_name}"
        SUFFIX ".elf"
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}")

    add_custom_command(TARGET "${target_name}" POST_BUILD
        COMMAND "${CMAKE_OBJCOPY}" -O binary
                "$<TARGET_FILE:${target_name}>"
                "${CMAKE_BINARY_DIR}/${test_name}.bin"
        COMMAND "${CMAKE_OBJDUMP}" -d -S
                "$<TARGET_FILE:${target_name}>"
                > "${CMAKE_BINARY_DIR}/${test_name}.dis"
        COMMENT "Generated ${test_name}.elf/.bin/.dis")
endfunction()

file(GLOB ASM_TESTS CONFIGURE_DEPENDS "${CMAKE_CURRENT_LIST_DIR}/*.S")
foreach(asm_src IN LISTS ASM_TESTS)
    get_filename_component(test_name "${asm_src}" NAME_WE)
    add_k10_manual_target("${test_name}" TYPE asm SRC "${asm_src}")
endforeach()

file(GLOB C_TESTS CONFIGURE_DEPENDS "${CMAKE_CURRENT_LIST_DIR}/*.c")
foreach(c_src IN LISTS C_TESTS)
    get_filename_component(test_name "${c_src}" NAME_WE)
    add_k10_manual_target("${test_name}" TYPE c SRC "${c_src}")
endforeach()
