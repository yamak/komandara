cmake_minimum_required(VERSION 3.23)

if(NOT DEFINED KOMANDARA_PRESET)
    message(FATAL_ERROR "KOMANDARA_PRESET must be provided by top-level CMakeLists.txt")
endif()

if(NOT KOMANDARA_PRESET STREQUAL "sim" AND NOT KOMANDARA_PRESET STREQUAL "genesys2")
    message(FATAL_ERROR "Unsupported KOMANDARA_PRESET='${KOMANDARA_PRESET}'")
endif()

set(KOMANDARA_ROOT "${CMAKE_SOURCE_DIR}")
set(KOMANDARA_BOOT_ADDR "2147483648")
set(KOMANDARA_FUSESOC_TARGET "sim")

if(KOMANDARA_PRESET STREQUAL "genesys2")
    set(KOMANDARA_FUSESOC_TARGET "genesys2_synth")
    find_program(VIVADO_BIN NAMES vivado)
    if(NOT VIVADO_BIN)
        message(FATAL_ERROR "vivado not found in PATH. Source scripts/vivado_env.sh before configuring genesys2 preset.")
    endif()

    set(KOMANDARA_BIT_FILE "${CMAKE_BINARY_DIR}/komandara_core_k10_0.1.0/genesys2_synth-vivado/komandara_core_k10_0.1.0.bit")
    configure_file("${KOMANDARA_ROOT}/cmake/program_fpga.sh.in" "${CMAKE_BINARY_DIR}/program_fpga.sh" @ONLY)
    file(CHMOD "${CMAKE_BINARY_DIR}/program_fpga.sh"
        PERMISSIONS
            OWNER_READ OWNER_WRITE OWNER_EXECUTE
            GROUP_READ GROUP_EXECUTE
            WORLD_READ WORLD_EXECUTE)
endif()

find_program(FUSESOC_BIN NAMES fusesoc HINTS "$ENV{VIRTUAL_ENV}/bin" REQUIRED)

if(NOT TARGET k10_selftest_meminit)
    message(FATAL_ERROR "Target k10_selftest_meminit not found. sw/k10 must be added before rtl.")
endif()

set(KOMANDARA_MEMINIT_HEX "${CMAKE_BINARY_DIR}/k10_c_selftest.hex")
set(KOMANDARA_FUSESOC_STAMP "${CMAKE_BINARY_DIR}/.komandara_fusesoc_build.stamp")

add_custom_command(
    OUTPUT "${KOMANDARA_FUSESOC_STAMP}"
    COMMAND "${FUSESOC_BIN}" --cores-root=${KOMANDARA_ROOT} run --target=${KOMANDARA_FUSESOC_TARGET} --build komandara:core:k10 --MEM_INIT=${KOMANDARA_MEMINIT_HEX} --BOOT_ADDR=${KOMANDARA_BOOT_ADDR}
    COMMAND "${CMAKE_COMMAND}" -E touch "${KOMANDARA_FUSESOC_STAMP}"
    DEPENDS "${KOMANDARA_MEMINIT_HEX}"
    WORKING_DIRECTORY "${KOMANDARA_ROOT}"
    COMMENT "Running FuseSoC target '${KOMANDARA_FUSESOC_TARGET}'"
    VERBATIM
)

add_custom_target(komandara_fusesoc_build ALL DEPENDS "${KOMANDARA_FUSESOC_STAMP}")
add_dependencies(komandara_fusesoc_build k10_selftest_meminit)

if(KOMANDARA_PRESET STREQUAL "sim")
    set(KOMANDARA_SIM_EXE "${CMAKE_BINARY_DIR}/Vkomandara")
    add_custom_command(
        OUTPUT "${KOMANDARA_SIM_EXE}"
        COMMAND "${CMAKE_COMMAND}" -DREPO_ROOT=${KOMANDARA_ROOT} -DOUTPUT_EXE=${KOMANDARA_SIM_EXE} -P "${KOMANDARA_ROOT}/cmake/copy_verilator_exe.cmake"
        DEPENDS "${KOMANDARA_FUSESOC_STAMP}"
        COMMENT "Copying Verilator executable to ${KOMANDARA_SIM_EXE}"
        VERBATIM
    )
    add_custom_target(verilator_exe ALL DEPENDS "${KOMANDARA_SIM_EXE}")
endif()
