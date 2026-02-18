if(NOT DEFINED REPO_ROOT)
    message(FATAL_ERROR "REPO_ROOT is required")
endif()

if(NOT DEFINED OUTPUT_EXE)
    message(FATAL_ERROR "OUTPUT_EXE is required")
endif()

set(BEST_CANDIDATE "${REPO_ROOT}/build/komandara_core_k10_0.1.0/sim-verilator/Vk10_tb")

if(NOT EXISTS "${BEST_CANDIDATE}")
    file(GLOB VERILATOR_CANDIDATES "${REPO_ROOT}/build/*/sim-verilator/Vk10_tb")
    list(LENGTH VERILATOR_CANDIDATES CANDIDATE_COUNT)
    if(CANDIDATE_COUNT EQUAL 0)
        message(FATAL_ERROR "Could not find Vk10_tb under ${REPO_ROOT}/build")
    endif()

    set(BEST_CANDIDATE "")
    set(BEST_TIMESTAMP "0")
    foreach(CANDIDATE IN LISTS VERILATOR_CANDIDATES)
        file(TIMESTAMP "${CANDIDATE}" CANDIDATE_TS "%s")
        if(CANDIDATE_TS GREATER BEST_TIMESTAMP)
            set(BEST_TIMESTAMP "${CANDIDATE_TS}")
            set(BEST_CANDIDATE "${CANDIDATE}")
        endif()
    endforeach()
endif()

execute_process(COMMAND "${CMAKE_COMMAND}" -E copy "${BEST_CANDIDATE}" "${OUTPUT_EXE}")
file(CHMOD "${OUTPUT_EXE}"
    PERMISSIONS
        OWNER_READ OWNER_WRITE OWNER_EXECUTE
        GROUP_READ GROUP_EXECUTE
        WORLD_READ WORLD_EXECUTE)

message(STATUS "Vkomandara copied from ${BEST_CANDIDATE}")
