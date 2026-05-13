#!/bin/bash
#===============================================================================
#  rmodus_install.sh — jednorázová instalace ROS 2 Jazzy + workspace na Raspberry Pi
#
#  Sekce (viz níže v souboru):
#    [0] Konfigurace
#    [1] Pomocné funkce (sparse git)
#    [2] Základní apt nástroje
#    [3] ROS 2 repozitář + balíčky + rosdep
#    [4] Stažení zdrojáků do workspace (sw-nav-module vč. rmodus_web, Xsens, rf2o)
#    [5] Xsens xspublic (make před colcon)
#    [6] rosdep + colcon build
#    [7] Shell: source ROS po přihlášení
#    [8] Práva k sériovým / USB portům (dialout, plugdev)
#    [9] udev (Xsens) + systemd služba rmodus
#   [10] Závěr
#===============================================================================
set -e

#-------------------------------------------------------------------------------
# [0] KONFIGURACE
#-------------------------------------------------------------------------------
WS_PATH="$HOME/rmodus_ws"
DEPLOY_PATH="$HOME/rmodus_setup"
ROS_DISTRO="jazzy"

echo ""
echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║  RMODUS — instalace ROS 2 ${ROS_DISTRO} + workspace                       ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo ""

#-------------------------------------------------------------------------------
# [1] POMOCNÉ FUNKCE — sparse checkout (Git ≥ 2.25)
#-------------------------------------------------------------------------------
sparse_clone() {
    local url=$1
    local branch=$2
    local target_dir=$3
    local folder_to_keep=$4
    local folder="${folder_to_keep%/}"

    echo "    [git sparse] ${folder}/ → $(basename "$target_dir")"

    if [ -d "$target_dir/.git" ]; then
        echo "         (složka už existuje — přeskočeno; pro čistý stav smažte $target_dir)"
        return 0
    fi

    mkdir -p "$(dirname "$target_dir")"
    rm -rf "$target_dir"

    # Vnořená cesta v repu → plný shallow clone + sparse-checkout --no-cone
    if [[ "$folder" == */* ]]; then
        git clone --depth 1 -b "$branch" "$url" "$target_dir"
        git -C "$target_dir" sparse-checkout init --no-cone
        git -C "$target_dir" sparse-checkout set "$folder"
    else
        git clone --depth 1 -b "$branch" --sparse "$url" "$target_dir"
        git -C "$target_dir" sparse-checkout set "$folder"
    fi
}

# Více kořenových složek z jednoho repa (např. rmodus_hw + rmodus_interface)
sparse_clone_flat_multi() {
    local url=$1
    local branch=$2
    local target_dir=$3
    shift 3
    local dirs=("$@")

    echo "    [git sparse] ${dirs[*]} → $(basename "$target_dir")"

    if [ -d "$target_dir/.git" ]; then
        echo "         (složka už existuje — přeskočeno; pro čistý stav smažte $target_dir)"
        return 0
    fi

    mkdir -p "$(dirname "$target_dir")"
    rm -rf "$target_dir"
    git clone --depth 1 -b "$branch" --sparse "$url" "$target_dir"
    git -C "$target_dir" sparse-checkout set "${dirs[@]}"
}

#-------------------------------------------------------------------------------
# [2] ZÁKLADNÍ APT — update, nástroje pro build a síť
#-------------------------------------------------------------------------------
echo "┌──────────────────────────────────────────────────────────────────────────┐"
echo "│ [2] Apt: aktualizace + curl, git, build-essential, pip                    │"
echo "└──────────────────────────────────────────────────────────────────────────┘"
sudo apt update && sudo apt upgrade -y
sudo apt install -y \
    curl gnupg2 lsb-release python3-pip \
    git build-essential

#-------------------------------------------------------------------------------
# [3] ROS 2 JAZZY — klíč, sources.list, ros-base, ros-dev-tools, rosdep
#-------------------------------------------------------------------------------
echo ""
echo "┌──────────────────────────────────────────────────────────────────────────┐"
echo "│ [3] ROS 2 ${ROS_DISTRO}: repozitář packages.ros.org, ros-base, ros-dev-tools │"
echo "└──────────────────────────────────────────────────────────────────────────┘"
sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" | sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null

sudo apt update
sudo apt install -y \
    ros-$ROS_DISTRO-ros-base \
    ros-dev-tools

# shellcheck source=/dev/null
source /opt/ros/$ROS_DISTRO/setup.bash

if [ ! -d "/etc/ros/rosdep/sources.list.d" ]; then
    sudo rosdep init
fi
rosdep update

#-------------------------------------------------------------------------------
# [4] WORKSPACE — stažení zdrojáků (sw-nav-module + Xsens + rf2o)
#-------------------------------------------------------------------------------
echo ""
echo "┌──────────────────────────────────────────────────────────────────────────┐"
echo "│ [4] Workspace $WS_PATH — klonování repozitářů                             │"
echo "└──────────────────────────────────────────────────────────────────────────┘"
mkdir -p "$WS_PATH/src"
cd "$WS_PATH"

echo "  (4a) R-MODUS/sw-nav-module → rmodus_hw, rmodus_web, rmodus_interface"
sparse_clone_flat_multi \
    "https://github.com/R-MODUS/sw-nav-module.git" \
    "main" \
    "$WS_PATH/src/sw_nav_module" \
    rmodus_hw \
    rmodus_web \
    rmodus_interface

SNAV_DIR="$WS_PATH/src/sw_nav_module"
if [ -d "$SNAV_DIR/.git" ] && {
    [ ! -f "$SNAV_DIR/rmodus_interface/package.xml" ] ||
        [ ! -f "$SNAV_DIR/rmodus_web/package.xml" ];
}; then
    echo "  (4a-fix) Doplňuji sparse-checkout: rmodus_hw rmodus_web rmodus_interface"
    git -C "$SNAV_DIR" sparse-checkout set rmodus_hw rmodus_web rmodus_interface
fi

echo "  (4b) Xsens MTi ROS2 driver (větev ros2)"
sparse_clone \
    "https://github.com/xsenssupport/Xsens_MTi_ROS_Driver_and_Ntrip_Client.git" \
    "ros2" \
    "$WS_PATH/src/xsens_mti_driver" \
    "src/xsens_mti_ros2_driver/"

echo "  (4c) rf2o_laser_odometry (větev ros2)"
RF2O_DIR="$WS_PATH/src/rf2o_laser_odometry"
if [ ! -d "$RF2O_DIR/.git" ]; then
    rm -rf "$RF2O_DIR"
    git clone --depth 1 -b ros2 https://github.com/MAPIRlab/rf2o_laser_odometry.git "$RF2O_DIR"
fi

#-------------------------------------------------------------------------------
# [5] XSENS — nativní knihovny před colcon (dokumentace výrobce)
#-------------------------------------------------------------------------------
echo ""
echo "┌──────────────────────────────────────────────────────────────────────────┐"
echo "│ [5] Xsens xspublic — make v lib/xspublic                                  │"
echo "└──────────────────────────────────────────────────────────────────────────┘"
XSPUBLIC_DIR="$WS_PATH/src/xsens_mti_driver/src/xsens_mti_ros2_driver/lib/xspublic"
if [ -d "$XSPUBLIC_DIR" ]; then
    (cd "$XSPUBLIC_DIR" && make)
else
    echo "         (xspublic nenalezen — přeskočeno)"
fi

if [ -z "$(find "$WS_PATH/src" -name package.xml -print -quit 2>/dev/null)" ]; then
    echo "CHYBA: v $WS_PATH/src není žádný package.xml (clone / síť / soukromé repo)." >&2
    exit 1
fi

#-------------------------------------------------------------------------------
# [6] ROSDEP + COLCON — závislosti a build (šetrné k RAM na Pi)
#-------------------------------------------------------------------------------
echo ""
echo "┌──────────────────────────────────────────────────────────────────────────┐"
echo "│ [6] rosdep install + colcon build (rf2o zvlášť kvůli RAM při linku)     │"
echo "└──────────────────────────────────────────────────────────────────────────┘"
rosdep install --from-paths src --ignore-src -y --rosdistro "$ROS_DISTRO" --skip-keys cmake_modules

export CMAKE_BUILD_PARALLEL_LEVEL="${CMAKE_BUILD_PARALLEL_LEVEL:-1}"
export MAKEFLAGS="${MAKEFLAGS:--j1}"

colcon build --symlink-install --parallel-workers 1 --packages-skip rf2o_laser_odometry

colcon build --symlink-install --parallel-workers 1 --packages-select rf2o_laser_odometry \
    --cmake-args \
    '-DCMAKE_EXE_LINKER_FLAGS=-Wl,--no-keep-memory' \
    '-DCMAKE_SHARED_LINKER_FLAGS=-Wl,--no-keep-memory'

if [ ! -f "$WS_PATH/install/setup.bash" ]; then
    echo "CHYBA: chybí $WS_PATH/install/setup.bash — build nedoběhl." >&2
    exit 1
fi

#-------------------------------------------------------------------------------
# [7] BASH — po přihlášení automaticky načíst ROS + workspace
#-------------------------------------------------------------------------------
echo ""
echo "┌──────────────────────────────────────────────────────────────────────────┐"
echo "│ [7] ~/.bashrc — source /opt/ros a install/setup.bash                      │"
echo "└──────────────────────────────────────────────────────────────────────────┘"
if [ -f "$HOME/.bashrc" ] && [ -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]; then
    if ! grep -qF "/opt/ros/${ROS_DISTRO}/setup.bash" "$HOME/.bashrc" 2>/dev/null; then
        {
            echo ""
            echo "# --- RMODUS (přidáno rmodus_install.sh) ---"
            echo "source /opt/ros/${ROS_DISTRO}/setup.bash"
            echo "test -f \"${WS_PATH}/install/setup.bash\" && source \"${WS_PATH}/install/setup.bash\""
        } >> "$HOME/.bashrc"
        echo "         Řádky přidány do ~/.bashrc"
    else
        echo "         ~/.bashrc už obsahuje source pro ROS — beze změny"
    fi
fi

#-------------------------------------------------------------------------------
# [8] SÉRIOVÉ / USB PORTY — skupiny dialout (+ plugdev pokud existuje)
#-------------------------------------------------------------------------------
echo ""
echo "┌──────────────────────────────────────────────────────────────────────────┐"
echo "│ [8] Práva k /dev/ttyUSB*, /dev/ttyACM* — skupiny dialout (a plugdev)      │"
echo "└──────────────────────────────────────────────────────────────────────────┘"
# dialout: typicky crw-rw---- root dialout u USB-UART (CH340, CP210x, FTDI…)
sudo usermod -aG dialout "$USER"
if getent group plugdev >/dev/null 2>&1; then
    sudo usermod -aG plugdev "$USER"
    echo "         Uživatel $USER přidán do: dialout, plugdev"
else
    echo "         Uživatel $USER přidán do: dialout (skupina plugdev na systému není)"
fi
echo "         → Skupiny platí po novém přihlášení nebo: newgrp dialout"
echo "         → LiDAR musí být připojený; port nemusí být ttyUSB0 (viz ls níže)."

#-------------------------------------------------------------------------------
# [9] UDEV (Xsens) + SYSTEMD služba rmodus
#-------------------------------------------------------------------------------
echo ""
echo "┌──────────────────────────────────────────────────────────────────────────┐"
echo "│ [9] udev pravidla (Xsens) + systemd unit rmodus.service                 │"
echo "└──────────────────────────────────────────────────────────────────────────┘"
if [ -d "$WS_PATH/src/xsens_mti_driver/src/xsens_mti_ros2_driver/resources" ]; then
    sudo cp "$WS_PATH/src/xsens_mti_driver/src/xsens_mti_ros2_driver/resources/99-xsens-mti.rules" /etc/udev/rules.d/
    sudo udevadm control --reload-rules && sudo udevadm trigger
    echo "         Xsens udev pravidla zkopírována."
else
    echo "         Xsens resources/ nenalezeny — udev přeskočeno."
fi

if [ -f "$DEPLOY_PATH/rmodus.service" ]; then
    sudo cp "$DEPLOY_PATH/rmodus.service" /etc/systemd/system/
    cp "$DEPLOY_PATH/rmodus_entrypoint.sh" "$HOME/"
    chmod +x "$HOME/rmodus_entrypoint.sh"
    sudo systemctl daemon-reload
    sudo systemctl enable rmodus.service
    echo "         Služba rmodus povolena (enable). Start po rebootu nebo: sudo systemctl start rmodus"
else
    echo "         $DEPLOY_PATH/rmodus.service nenalezen — systemd přeskočeno."
fi

#-------------------------------------------------------------------------------
# [10] ZÁVĚR
#-------------------------------------------------------------------------------
echo ""
echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║  HOTOVÉ                                                                  ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo "  • Obnovte skupiny:  newgrp dialout   NEBO   odhlášení / restart Pi"
echo "  • ROS v shellu:     source ~/.bashrc"
echo "  • Ověření:           ros2 doctor"
echo "  • Sériové porty:    ls -l /dev/ttyUSB* /dev/ttyACM* 2>/dev/null || true"
echo "    (FileNotFoundError na /dev/ttyUSB0 = zařízení neexistuje nebo jiný název portu)"
echo ""
