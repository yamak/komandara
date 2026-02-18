cmake_minimum_required(VERSION 3.23)

project(komandara C ASM)

if(NOT DEFINED ENV{VIRTUAL_ENV} OR "$ENV{VIRTUAL_ENV}" STREQUAL "")
    message(FATAL_ERROR "Python virtual environment is not active. Run: source .venv/bin/activate")
endif()

set(KOMANDARA_PRESET "" CACHE STRING "Build flavor: sim or genesys2")
set_property(CACHE KOMANDARA_PRESET PROPERTY STRINGS sim genesys2)

if(NOT KOMANDARA_PRESET)
    message(FATAL_ERROR "KOMANDARA_PRESET is not set. Use CMake preset 'komandara-sim' or 'komandara-genesys2'.")
endif()

if(NOT KOMANDARA_PRESET STREQUAL "sim" AND NOT KOMANDARA_PRESET STREQUAL "genesys2")
    message(FATAL_ERROR "Unsupported KOMANDARA_PRESET='${KOMANDARA_PRESET}'. Expected 'sim' or 'genesys2'.")
endif()

set(KOMANDARA_ROOT "${CMAKE_SOURCE_DIR}")
set(K10_REAL_HW_LOGS OFF)
if(KOMANDARA_PRESET STREQUAL "genesys2")
    set(K10_REAL_HW_LOGS ON)
endif()

add_subdirectory(sw/k10)
add_subdirectory(rtl)
