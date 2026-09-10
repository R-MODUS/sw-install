#!/usr/bin/env bash
# Stahne sw-install do ~/rmodus/setup, doinstaluje python3 / git, spusti install.py
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export PYTHONUNBUFFERED=1
# Ubuntu 24.04+ / PEP 668: rosdep pip install (jako root) vyzaduje --break-system-packages
export PIP_BREAK_SYSTEM_PACKAGES=1

RMODUS_ROOT="${RMODUS_ROOT:-${HOME}/rmodus}"
REPO_URL="${RMODUS_REPO_URL:-https://github.com/R-MODUS/sw-install.git}"
REPO_DIR="${RMODUS_REPO_DIR:-${RMODUS_ROOT}/setup}"

echo "[bootstrap] Strom adresaru:"
echo "  ${RMODUS_ROOT}/setup     (tento repozitar: instalator, examples, network, systemd)"
echo "  ${RMODUS_ROOT}/ros2_ws   (colcon workspace)"
echo "  ${RMODUS_ROOT}/configs   (profiles/, active, network.yaml)"
echo "  ${RMODUS_ROOT}/data      (manual.pdf, data)"
mkdir -p "${RMODUS_ROOT}/setup" "${RMODUS_ROOT}/ros2_ws/src" "${RMODUS_ROOT}/configs/profiles" "${RMODUS_ROOT}/data"
touch "${RMODUS_ROOT}/configs/.gitkeep" "${RMODUS_ROOT}/data/.gitkeep" 2>/dev/null || true

_apt_update_once() {
  if [[ -z "${_RMODUS_BOOT_APT:-}" ]]; then
    sudo apt-get update
    _RMODUS_BOOT_APT=1
  fi
}

if ! command -v python3 >/dev/null 2>&1; then
  _apt_update_once
  sudo apt-get install -y python3-minimal python3
fi
if ! command -v git >/dev/null 2>&1; then
  _apt_update_once
  sudo apt-get install -y git
fi

_apt_update_once
sudo apt-get install -y curl ca-certificates

if [[ -d "${REPO_DIR}/.git" ]]; then
  git -C "${REPO_DIR}" pull
else
  git clone "${REPO_URL}" "${REPO_DIR}"
fi

INSTALL_PY="${REPO_DIR}/install.py"
if [[ ! -f "${INSTALL_PY}" ]]; then
  echo "" >&2
  echo "CHYBA: v ${REPO_DIR} chybi install.py - na GitHubu je pravdepodobne starsi main (nebyl push)." >&2
  echo "  Po pushnuti zmen:  cd ${REPO_DIR} && git fetch origin && git reset --hard origin/main" >&2
  echo "  Obsah adresare:" >&2
  ls -la "${REPO_DIR}" >&2
  exit 1
fi
chmod +x "${INSTALL_PY}" 2>/dev/null || true
exec python3 -u "${INSTALL_PY}" "$@"
