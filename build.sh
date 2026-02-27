#!/bin/bash
set -e

if [ -z "$1" ]; then
    echo "Usage: ./build.sh [sim|genesys2]"
    exit 1
fi

TARGET=$1
if [ "$TARGET" != "sim" ] && [ "$TARGET" != "genesys2" ]; then
    echo "Unsupported target: $TARGET"
    echo "Usage: ./build.sh [sim|genesys2]"
    exit 1
fi

# 1. Setup tools and venv if not present
if [ ! -d ".venv" ]; then
    echo "Virtual environment not discovered. Running first-time setup..."
    ./scripts/setup_tools.sh
fi

source .venv/bin/activate



# 2. Compile SW and generate MEM_INIT hex
echo "=== Building Software ==="
mkdir -p build/sw
cd build/sw

if [ "$TARGET" == "genesys2" ]; then
    /usr/bin/cmake -DCMAKE_TOOLCHAIN_FILE=../../sw/k10/riscv32.cmake -DK10_REAL_HW_LOGS=ON ../../sw/k10
else
    /usr/bin/cmake -DCMAKE_TOOLCHAIN_FILE=../../sw/k10/riscv32.cmake -DK10_REAL_HW_LOGS=OFF ../../sw/k10
fi

make
cd ../..

K10_MEMINIT_HEX="$(pwd)/build/sw/k10_c_selftest.hex"
if [ ! -f "$K10_MEMINIT_HEX" ]; then
    echo "ERROR: SW build failed to produce $K10_MEMINIT_HEX"
    exit 1
fi

# 3. Package VSCode Wizard Extension
echo "=== Packaging VSCode Wizard ==="
echo "export const KOMANDARA_ROOT = '$(pwd)';" > vscode_ext/komandara-wizard/src/config.ts
cd vscode_ext/komandara-wizard
npm install
npm run compile
npx @vscode/vsce package --out ../../build/komandara-wizard.vsix --no-dependencies
cd ../..
echo "VSCode extension packaged to build/komandara-wizard.vsix"

# 4. Build Hardware with FuseSoC
echo "=== Building Hardware ($TARGET) ==="
FUSESOC_TARGET="sim"
if [ "$TARGET" == "genesys2" ]; then
    FUSESOC_TARGET="genesys2_synth"
fi

fusesoc --cores-root=. run --target=${FUSESOC_TARGET} --build komandara:core:k10 --MEM_INIT=${K10_MEMINIT_HEX} --BOOT_ADDR=2147483648

if [ "$TARGET" == "sim" ]; then
    SIM_BIN="build/komandara_core_k10_0.1.0/sim-verilator/Vk10_tb"
    ln -sf "$(pwd)/${SIM_BIN}" build/Vk10
    echo ""
    echo "Build complete!"
    echo "  Verilator model : build/Vk10"
else
    BIT_DIR="build/komandara_core_k10_0.1.0/genesys2_synth-vivado/komandara_core_k10_0.1.0.runs/impl_1"
    BIT_FILE="${BIT_DIR}/k10_genesys2_top.bit"
    ln -sf "$(pwd)/${BIT_FILE}" build/k10.bit
    ln -sf "$(pwd)/scripts/fpga_run.sh" build/fpga_run.sh
    ln -sf "$(pwd)/scripts/vivado_program_fpga.tcl" build/vivado_program_fpga.tcl

    echo ""
    echo "Build complete!"
    echo "  Bitstream : build/k10.bit"
    echo "  Program   : ./build/fpga_run.sh"
fi
