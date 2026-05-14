#!/usr/bin/env bash
# Stáhne sw-install, doinstaluje python3 / git, spustí install.py
set -euo pipefail

# Tiší needrestart / méně překrývaného výstupu při apt v SSH
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

REPO_URL="${RMODUS_REPO_URL:-https://github.com/R-MODUS/sw-install.git}"
REPO_DIR="${RMODUS_REPO_DIR:-${HOME}/rmodus_setup}"

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
  echo "CHYBA: v ${REPO_DIR} chybí install.py — na GitHubu je pravděpodobně starší main (nebyl push)." >&2
  echo "  Po pushnutí změn spusťte na Pi:  cd ${REPO_DIR} && git fetch origin && git reset --hard origin/main" >&2
  echo "  Obsah adresáře:" >&2
  ls -la "${REPO_DIR}" >&2
  exit 1
fi
chmod +x "${INSTALL_PY}" 2>/dev/null || true
# -u = nebufferovaný výstup (print z install.py hned viditelný v SSH)
exec python3 -u "${INSTALL_PY}" "$@"
