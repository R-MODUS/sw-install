#!/usr/bin/env bash
# Zpětná kompatibilita — hlavní logika je v install.py
cd "$(dirname "${BASH_SOURCE[0]:-$0}")" || exit 1
export PYTHONUNBUFFERED=1
exec python3 -u ./install.py "$@"
