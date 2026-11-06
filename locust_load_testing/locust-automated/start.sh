#!/usr/bin/env bash
# =============================================================================
# CampusHub Locust Automation Suite Launcher
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENV_PYTHON="${ROOT_DIR}/.venv/bin/python"

if [ ! -f "${VENV_PYTHON}" ]; then
    echo "[*] Virtual environment not found at: ${ROOT_DIR}/.venv"
    echo "[*] Initializing Python virtual environment..."
    python3 -m venv "${ROOT_DIR}/.venv"
    echo "[*] Installing dependencies..."
    if [ -f "${ROOT_DIR}/requirements.txt" ]; then
        "${ROOT_DIR}/.venv/bin/pip" install --upgrade pip
        "${ROOT_DIR}/.venv/bin/pip" install -r "${ROOT_DIR}/requirements.txt"
    else
        "${ROOT_DIR}/.venv/bin/pip" install locust requests pyjwt matplotlib pillow psutil
    fi
fi

echo "[*] Launching CampusHub Locust GUI Suite..."
cd "${SCRIPT_DIR}"
exec "${VENV_PYTHON}" app.py "$@"
