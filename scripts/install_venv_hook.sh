#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

if [[ -n "${VIRTUAL_ENV:-}" ]]; then
    ACTIVATE_FILE="${VIRTUAL_ENV}/bin/activate"
else
    ACTIVATE_FILE="${PROJECT_ROOT}/.venv/bin/activate"
fi

if [[ ! -f "${ACTIVATE_FILE}" ]]; then
    echo "ERROR: activate file not found: ${ACTIVATE_FILE}" >&2
    echo "Create venv first: python3 -m venv .venv" >&2
    exit 1
fi

BEGIN_MARK="# >>> komandara env hook >>>"
END_MARK="# <<< komandara env hook <<<"

TMP_FILE="$(mktemp)"
awk -v begin="${BEGIN_MARK}" -v end="${END_MARK}" '
    $0 == begin {skip=1; next}
    $0 == end   {skip=0; next}
    !skip       {print}
' "${ACTIVATE_FILE}" > "${TMP_FILE}"

cat >> "${TMP_FILE}" <<'EOF'
# >>> komandara env hook >>>
if [ -n "${VIRTUAL_ENV:-}" ] && [ -f "${VIRTUAL_ENV}/../scripts/env.sh" ]; then
    . "${VIRTUAL_ENV}/../scripts/env.sh"
fi
# <<< komandara env hook <<<
EOF

mv "${TMP_FILE}" "${ACTIVATE_FILE}"

echo "[install_venv_hook] Installed Komandara env auto-source hook into ${ACTIVATE_FILE}"
