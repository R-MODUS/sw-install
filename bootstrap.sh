#!/bin/bash
set -e

REPO_URL="https://github.com/R-MODUS/sw-install.git"
REPO_DIR="$HOME/rmodus_setup"

sudo apt update
sudo apt install -y git

if [ -d "$REPO_DIR" ]; then
    cd "$REPO_DIR"
    git pull
else
    git clone "$REPO_URL" "$REPO_DIR"
fi

chmod +x "$REPO_DIR/rmodus_install.sh"
bash "$REPO_DIR/rmodus_install.sh"