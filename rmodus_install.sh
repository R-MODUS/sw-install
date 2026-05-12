#!/bin/bash
set -e

# --- 1. KONFIGURACE ---
WS_PATH="$HOME/rmodus_ws"
DEPLOY_PATH="$HOME/rmodus_setup"
ROS_DISTRO="jazzy"

echo "===================================================="
echo "START INSTALACE FRAMEWORKU RMODUS (ROS 2 $ROS_DISTRO)"
echo "===================================================="

# --- 2. SPARSE CLONE (git >= 2.25; spolehlivější než init + pull u prázdného repo) ---
sparse_clone() {
    local url=$1
    local branch=$2
    local target_dir=$3
    local folder_to_keep=$4
    local folder="${folder_to_keep%/}"

    echo "--> Selektivně stahuji: ${folder}/"

    if [ -d "$target_dir/.git" ]; then
        echo "    Již existuje $target_dir — přeskočeno (smažte složku pro čisté znovustažení)."
        return 0
    fi

    mkdir -p "$(dirname "$target_dir")"
    rm -rf "$target_dir"

    # Top-level složka: clone --sparse. Vnořená cesta: plný shallow clone + no-cone (spolehlivější).
    if [[ "$folder" == */* ]]; then
        git clone --depth 1 -b "$branch" "$url" "$target_dir"
        git -C "$target_dir" sparse-checkout init --no-cone
        git -C "$target_dir" sparse-checkout set "$folder"
    else
        git clone --depth 1 -b "$branch" --sparse "$url" "$target_dir"
        git -C "$target_dir" sparse-checkout set "$folder"
    fi
}

# Více top-level složek z jednoho repa (např. rmodus_hw + rmodus_interface ve sw-nav-module).
sparse_clone_flat_multi() {
    local url=$1
    local branch=$2
    local target_dir=$3
    shift 3
    local dirs=("$@")

    echo "--> Selektivně stahuji: ${dirs[*]}"

    if [ -d "$target_dir/.git" ]; then
        echo "    Již existuje $target_dir — přeskočeno (smažte složku pro čisté znovustažení)."
        return 0
    fi

    mkdir -p "$(dirname "$target_dir")"
    rm -rf "$target_dir"
    git clone --depth 1 -b "$branch" --sparse "$url" "$target_dir"
    git -C "$target_dir" sparse-checkout set "${dirs[@]}"
}

# --- 3. SYSTÉMOVÝ UPDATE A ZÁKLADNÍ NÁSTROJE ---
sudo apt update && sudo apt upgrade -y
sudo apt install -y \
    curl gnupg2 lsb-release python3-pip \
    git build-essential

# --- 4. INSTALACE ROS 2 JAZZY (bez Nav2 / SLAM z apt; vlastní zdrojáky ve workspace) ---
sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" | sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null

sudo apt update
# ros-dev-tools = oficiální meta-balík (colcon, vcstool, rosdep, …). Není to ros-jazzy-dev-tools.
sudo apt install -y \
    ros-$ROS_DISTRO-ros-base \
    ros-dev-tools

# Prostředí ROS (nutné pro rosdep a colcon)
# shellcheck source=/dev/null
source /opt/ros/$ROS_DISTRO/setup.bash

# Inicializace rosdep
if [ ! -d "/etc/ros/rosdep/sources.list.d" ]; then
    sudo rosdep init
fi
rosdep update

# --- 5. PŘÍPRAVA WORKSPACE A STAŽENÍ KÓDŮ ---
mkdir -p "$WS_PATH/src"
cd "$WS_PATH"

# A: sw-nav-module — rmodus_hw + rmodus_interface (rosdep u rmodus_hw vyžaduje zdroj rmodus_interface)
sparse_clone_flat_multi \
    "https://github.com/R-MODUS/sw-nav-module.git" \
    "main" \
    "$WS_PATH/src/sw_nav_module" \
    rmodus_hw \
    rmodus_interface

# B: Xsens MTi ROS 2 driver (viz https://github.com/xsenssupport/Xsens_MTi_ROS_Driver_and_Ntrip_Client/tree/ros2/src/xsens_mti_ros2_driver)
sparse_clone \
    "https://github.com/xsenssupport/Xsens_MTi_ROS_Driver_and_Ntrip_Client.git" \
    "ros2" \
    "$WS_PATH/src/rmodus_drivers/xsens_mti_driver" \
    "src/xsens_mti_ros2_driver/"

# C: rf2o_laser_odometry (větev ros2, viz https://github.com/MAPIRlab/rf2o_laser_odometry)
echo "--> Stahuji rf2o_laser_odometry (větev ros2)"
RF2O_DIR="$WS_PATH/src/rf2o_laser_odometry"
if [ ! -d "$RF2O_DIR/.git" ]; then
    rm -rf "$RF2O_DIR"
    git clone --depth 1 -b ros2 https://github.com/MAPIRlab/rf2o_laser_odometry.git "$RF2O_DIR"
fi

# --- 6. XSPUBLIC (povinný krok před colcon podle dokumentace Xsens) ---
XSPUBLIC_DIR="$WS_PATH/src/rmodus_drivers/xsens_mti_driver/src/xsens_mti_ros2_driver/lib/xspublic"
if [ -d "$XSPUBLIC_DIR" ]; then
    echo "--> Sestavuji xsens xspublic"
    (cd "$XSPUBLIC_DIR" && make)
fi

# Žádný package.xml => rosdep/colcon nedávají smysl (často rozbitý clone nebo soukromé repo)
if [ -z "$(find "$WS_PATH/src" -name package.xml -print -quit 2>/dev/null)" ]; then
    echo "CHYBA: ve $WS_PATH/src není žádný package.xml — zkontrolujte sparse clone a přístup k GitHubu." >&2
    exit 1
fi

# --- 7. INSTALACE ZÁVISLOSTÍ A BUILD ---
# cmake_modules: rf2o ho má v package.xml, ale na ROS 2 Jazzy v rosdistro není rozumný apt záznam (legacy).
rosdep install --from-paths src --ignore-src -y --rosdistro "$ROS_DISTRO" --skip-keys cmake_modules

# Omezení na 2 workery kvůli 4GB RAM na Pi 4
colcon build --symlink-install --parallel-workers 2

if [ ! -f "$WS_PATH/install/setup.bash" ]; then
    echo "CHYBA: colcon nedorazil do konce — chybí $WS_PATH/install/setup.bash. Výše hledejte chybu buildu." >&2
    exit 1
fi

# ROS ve výchozím bashi (jinak v novém SSH: ros2: command not found — source byl jen uvnitř tohoto skriptu)
if [ -f "$HOME/.bashrc" ] && [ -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]; then
    if ! grep -qF "/opt/ros/${ROS_DISTRO}/setup.bash" "$HOME/.bashrc" 2>/dev/null; then
        {
            echo ""
            echo "# Přidáno rmodus_install.sh — ROS 2 ${ROS_DISTRO}"
            echo "source /opt/ros/${ROS_DISTRO}/setup.bash"
            echo "test -f \"${WS_PATH}/install/setup.bash\" && source \"${WS_PATH}/install/setup.bash\""
        } >> "$HOME/.bashrc"
    fi
fi

# --- 8. HARDWARE A SYSTÉMOVÉ SLUŽBY ---
sudo usermod -aG dialout "$USER"

# Udev pravidla pro Xsens (pokud existují v sparse stažení)
if [ -d "src/rmodus_drivers/xsens_mti_driver/src/xsens_mti_ros2_driver/resources" ]; then
    sudo cp src/rmodus_drivers/xsens_mti_driver/src/xsens_mti_ros2_driver/resources/99-xsens-mti.rules /etc/udev/rules.d/
    sudo udevadm control --reload-rules && sudo udevadm trigger
fi

# Nastavení systemd služby (předpoklad uživatele admin — viz rmodus.service)
if [ -f "$DEPLOY_PATH/rmodus.service" ]; then
    sudo cp "$DEPLOY_PATH/rmodus.service" /etc/systemd/system/
    cp "$DEPLOY_PATH/rmodus_entrypoint.sh" "$HOME/"
    chmod +x "$HOME/rmodus_entrypoint.sh"
    sudo systemctl daemon-reload
    sudo systemctl enable rmodus.service
fi

echo "===================================================="
echo "INSTALACE DOKONČENA."
echo "  • V tomto SSH okně:  source ~/.bashrc   (nebo se znovu přihlaste)"
echo "  • Ověření:          ros2 doctor"
echo "  • Restart Pi (doporučeno: dialout + systemd)."
echo "===================================================="
