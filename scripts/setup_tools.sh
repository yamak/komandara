#!/usr/bin/env bash
# =============================================================================
# Komandara — Verification Tool Setup Script
# =============================================================================
# One-time setup script. Builds and installs all verification tools into
# the project-local tools/ directory.
#
# Usage:
#   python3 -m venv .venv
#   source .venv/bin/activate
#   ./scripts/setup_tools.sh
#
# After setup, daily usage is:
#   source .venv/bin/activate
# (scripts/env.sh is auto-sourced by a hook installed into venv activate)
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TOOLS_DIR="${PROJECT_ROOT}/tools"
TOOLS_SRC="${TOOLS_DIR}/src"

# Tool versions (pinned for reproducibility)
VERILATOR_VERSION="v5.028"
SPIKE_VERSION="master"
RISCV_DV_VERSION="master"
RISCV_TOOLCHAIN_TAG="2024.09.03"

# Parallelism
NPROC=$(nproc 2>/dev/null || echo 4)

# ---------------------------------------------------------------------------
# Colors & Helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERR]${NC}   $*" >&2; }
step()  { echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

die() { err "$@"; exit 1; }

# ---------------------------------------------------------------------------
# Pre-flight Checks
# ---------------------------------------------------------------------------
step "Pre-flight Checks"

# Check we're in a venv
if [[ -z "${VIRTUAL_ENV:-}" ]]; then
    die "Python virtual environment is not active!\n  Run: python3 -m venv .venv && source .venv/bin/activate"
fi
ok "Python venv active: ${VIRTUAL_ENV}"

# Sanity check: ensure venv python is real CPython, not Cursor/Electron wrapper
VENV_PYTHON="$(readlink -f "$(which python3)")"
if echo "${VENV_PYTHON}" | grep -qi "cursor\|electron\|AppImage"; then
    warn "venv python points to Cursor/Electron wrapper: ${VENV_PYTHON}"
    info "Fixing venv symlinks to use system Python..."
    REAL_PYTHON="$(readlink -f /usr/bin/python3)"
    cd "${VIRTUAL_ENV}/bin"
    rm -f python python3 python3.*[!-]*
    ln -s "${REAL_PYTHON}" "$(basename "${REAL_PYTHON}")"
    ln -s "$(basename "${REAL_PYTHON}")" python3
    ln -s python3 python
    cd "${PROJECT_ROOT}"
    # Re-verify
    VENV_PYTHON="$(readlink -f "$(which python3)")"
    ok "Fixed venv python → ${VENV_PYTHON}"
else
    ok "venv python is real CPython: ${VENV_PYTHON}"
fi

# Check system dependencies
MISSING_PKGS=()
check_pkg() {
    if ! dpkg -s "$1" &>/dev/null; then
        MISSING_PKGS+=("$1")
    fi
}

REQUIRED_PKGS=(
    git make autoconf g++ flex bison ccache
    libfl-dev libfl2 zlib1g-dev
    device-tree-compiler
    libboost-all-dev
    perl
    python3-venv
    curl
    help2man
)

for pkg in "${REQUIRED_PKGS[@]}"; do
    check_pkg "$pkg"
done

if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
    err "Missing system packages: ${MISSING_PKGS[*]}"
    echo ""
    echo "  Install them with:"
    echo "    sudo apt-get install -y ${MISSING_PKGS[*]}"
    echo ""
    die "Install missing packages and re-run this script."
fi
ok "All system dependencies satisfied"

# Check cmake
if ! command -v cmake &>/dev/null; then
    die "cmake not found. Install with: sudo apt-get install -y cmake"
fi
ok "cmake found: $(cmake --version 2>/dev/null | head -1 || echo 'available')"

# ---------------------------------------------------------------------------
# Directory Setup
# ---------------------------------------------------------------------------
step "Setting Up Directories"

mkdir -p "${TOOLS_DIR}"
mkdir -p "${TOOLS_SRC}"
ok "tools/ directory ready"

# ---------------------------------------------------------------------------
# 1. Python Packages
# ---------------------------------------------------------------------------
step "1/5 — Installing Python Packages"

pip install --upgrade pip setuptools wheel 2>&1 | tail -1
pip install -r "${PROJECT_ROOT}/python-requirements.txt" 2>&1 | tail -3
ok "Python packages installed"

# ---------------------------------------------------------------------------
# 2. Verilator
# ---------------------------------------------------------------------------
VERILATOR_PREFIX="${TOOLS_DIR}/verilator"

step "2/5 — Verilator (${VERILATOR_VERSION})"

if [[ -x "${VERILATOR_PREFIX}/bin/verilator" ]]; then
    ok "Verilator already installed — skipping"
else
    VERILATOR_SRC="${TOOLS_SRC}/verilator"

    if [[ ! -d "${VERILATOR_SRC}" ]]; then
        info "Cloning Verilator ${VERILATOR_VERSION} (need full history for git describe)..."
        git clone --branch "${VERILATOR_VERSION}" \
            https://github.com/verilator/verilator.git "${VERILATOR_SRC}"
    fi

    info "Building Verilator (this may take several minutes)..."
    cd "${VERILATOR_SRC}"

    # Unset ELECTRON / Cursor IDE env vars that interfere with Python sub-processes
    unset ELECTRON_RUN_AS_NODE 2>/dev/null || true

    autoconf
    ./configure --prefix="${VERILATOR_PREFIX}"

    # Phase 1: Generate all auto-generated headers sequentially
    info "  Phase 1/2: Generating code (sequential)..."
    make -j1 -C src ../bin/verilator_bin 2>&1 | tail -5 || true

    # Phase 2: Full parallel build
    info "  Phase 2/2: Compiling (parallel, ${NPROC} jobs)..."
    make -j"${NPROC}"
    make install
    cd "${PROJECT_ROOT}"

    ok "Verilator installed to ${VERILATOR_PREFIX}"
fi

# Verify (unset VERILATOR_ROOT to let the installed binary self-locate)
unset VERILATOR_ROOT 2>/dev/null || true
"${VERILATOR_PREFIX}/bin/verilator" --version
ok "Verilator verification passed"

# ---------------------------------------------------------------------------
# 3. Spike (RISC-V ISA Simulator)
# ---------------------------------------------------------------------------
SPIKE_PREFIX="${TOOLS_DIR}/spike"

step "3/5 — Spike (riscv-isa-sim)"

if [[ -x "${SPIKE_PREFIX}/bin/spike" ]]; then
    ok "Spike already installed — skipping"
else
    SPIKE_SRC="${TOOLS_SRC}/riscv-isa-sim"

    if [[ ! -d "${SPIKE_SRC}" ]]; then
        info "Cloning Spike..."
        git clone --depth 1 \
            https://github.com/riscv-software-src/riscv-isa-sim.git "${SPIKE_SRC}"
    fi

    info "Building Spike..."
    mkdir -p "${SPIKE_SRC}/build"
    cd "${SPIKE_SRC}/build"
    ../configure --prefix="${SPIKE_PREFIX}"
    make -j"${NPROC}"
    make install
    cd "${PROJECT_ROOT}"

    ok "Spike installed to ${SPIKE_PREFIX}"
fi

# Verify (use || true to avoid SIGPIPE from head)
SPIKE_VER=$("${SPIKE_PREFIX}/bin/spike" --help 2>&1 | head -1 || true)
echo "  ${SPIKE_VER}"
ok "Spike verification passed"

# ---------------------------------------------------------------------------
# 4. RISC-V GNU Toolchain (pre-built binary)
# ---------------------------------------------------------------------------
RISCV_TC_PREFIX="${TOOLS_DIR}/riscv-toolchain"

step "4/5 — RISC-V GNU Toolchain (riscv32-unknown-elf)"

if [[ -x "${RISCV_TC_PREFIX}/bin/riscv32-unknown-elf-gcc" ]]; then
    ok "RISC-V toolchain already installed — skipping"
else
    ARCH=$(uname -m)
    if [[ "${ARCH}" != "x86_64" ]]; then
        die "Pre-built toolchain only available for x86_64. Got: ${ARCH}"
    fi

    TC_TARBALL="riscv32-elf-ubuntu-22.04-gcc-nightly-${RISCV_TOOLCHAIN_TAG}-nightly.tar.gz"
    TC_URL="https://github.com/riscv-collab/riscv-gnu-toolchain/releases/download/${RISCV_TOOLCHAIN_TAG}/${TC_TARBALL}"

    info "Downloading RISC-V toolchain (this may take a while)..."
    mkdir -p "${TOOLS_SRC}"
    curl -L --progress-bar -o "${TOOLS_SRC}/${TC_TARBALL}" "${TC_URL}"

    info "Extracting toolchain..."
    mkdir -p "${RISCV_TC_PREFIX}"
    tar xzf "${TOOLS_SRC}/${TC_TARBALL}" -C "${RISCV_TC_PREFIX}" --strip-components=1

    # Clean up tarball
    rm -f "${TOOLS_SRC}/${TC_TARBALL}"

    ok "RISC-V toolchain installed to ${RISCV_TC_PREFIX}"
fi

# Verify
TC_VER=$("${RISCV_TC_PREFIX}/bin/riscv32-unknown-elf-gcc" --version | head -1 || true)
echo "  ${TC_VER}"
ok "RISC-V toolchain verification passed"

# ---------------------------------------------------------------------------
# 5. RISC-V DV (Google Random Instruction Generator)
# ---------------------------------------------------------------------------
RISCV_DV_DIR="${TOOLS_DIR}/riscv-dv"

step "5/5 — RISC-V DV"

if [[ -d "${RISCV_DV_DIR}" ]]; then
    ok "riscv-dv already cloned — skipping"
else
    info "Cloning riscv-dv..."
    git clone --depth 1 \
        https://github.com/google/riscv-dv.git "${RISCV_DV_DIR}"
    ok "riscv-dv cloned to ${RISCV_DV_DIR}"
fi

# Install riscv-dv Python requirements if they exist
if [[ -f "${RISCV_DV_DIR}/requirements.txt" ]]; then
    info "Installing riscv-dv Python dependencies..."
    pip install -r "${RISCV_DV_DIR}/requirements.txt" 2>&1 | tail -3
fi

ok "riscv-dv ready"

# ---------------------------------------------------------------------------
# Verify env.sh exists
# ---------------------------------------------------------------------------
step "Checking scripts/env.sh"

if [[ -f "${SCRIPT_DIR}/env.sh" ]]; then
    ok "scripts/env.sh exists (portable, uses BASH_SOURCE for path resolution)"
else
    die "scripts/env.sh not found! It should be part of the repository."
fi

step "Installing venv activate hook"

"${SCRIPT_DIR}/install_venv_hook.sh"
ok "venv activate hook installed"

# ---------------------------------------------------------------------------
# Final Verification Summary
# ---------------------------------------------------------------------------
step "Setup Complete — Verification Summary"

echo ""
printf "  %-25s %s\n" "Verilator:" "$("${VERILATOR_PREFIX}/bin/verilator" --version 2>/dev/null)"
printf "  %-25s %s\n" "Spike:" "$("${SPIKE_PREFIX}/bin/spike" --help 2>&1 | head -1 || true)"
printf "  %-25s %s\n" "RISC-V GCC:" "$("${RISCV_TC_PREFIX}/bin/riscv32-unknown-elf-gcc" --version | head -1 || true)"
printf "  %-25s %s\n" "riscv-dv:" "${RISCV_DV_DIR}"
printf "  %-25s %s\n" "Python venv:" "${VIRTUAL_ENV}"
printf "  %-25s %s\n" "FuseSoC:" "$(fusesoc --version 2>/dev/null || echo 'not found')"
echo ""

ok "All tools installed successfully!"
echo ""
info "To use in a new terminal session:"
echo "    source .venv/bin/activate"
echo ""
