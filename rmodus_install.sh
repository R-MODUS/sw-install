#!/bin/bash
#===============================================================================
#  rmodus_install.sh — jednorázová instalace ROS 2 Jazzy + workspace na Raspberry Pi
#
#  Volitelná konfigurace: rmodus_install.conf (zkopírujte z rmodus_install.conf.example)
#    nebo: export RMODUS_INSTALL_CONF=/cesta/k/conf
#
#  Sekce:
#    [0] Konfigurace + načtení .conf
#    [1] Pomocné funkce (sparse git)
#    [2] Základní apt
#    [3] ROS 2 + rosdep
#    [4] Stažení zdrojáků (podle .conf)
#    [5] Xsens xspublic (make) — volitelné
#    [6a] rosdep install
#    [6b] colcon — workspace (bez rf2o, pokud je rf2o zapnutý)
#    [6c] colcon — jen rf2o (pokud zapnuto)
#    [7] ~/.bashrc
#    [8] Sériové porty (skupiny)
#    [9a] udev Xsens — volitelné
#    [9b] systemd rmodus — volitelné
#   [10] Závěr
#===============================================================================
set -e

#-------------------------------------------------------------------------------
# [0] KONFIGURACE
#-------------------------------------------------------------------------------
INSTALL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROS_DISTRO="jazzy"
WS_PATH="${WS_PATH:-$HOME/rmodus_ws}"
DEPLOY_PATH="${DEPLOY_PATH:-$HOME/rmodus_setup}"

# Výchozí přepínače (přepíše je soubor rmodus_install.conf nebo $RMODUS_INSTALL_CONF)
FETCH_SW_NAV_MODULE=1
SW_NAV_SPARSE_DIRS="rmodus_hw rmodus_web rmodus_interface"
SW_NAV_BRANCH="main"
FETCH_XSENS_DRIVER=1
BUILD_XSPUBLIC=1
INSTALL_XSENS_UDEV=1
FETCH_RF2O=1
BUILD_RF2O_SEPARATE_PHASE=1
ENABLE_SYSTEMD_RMODUS=1

RMODUS_INSTALL_CONF="${RMODUS_INSTALL_CONF:-$INSTALL_SCRIPT_DIR/rmodus_install.conf}"
if [ -f "$RMODUS_INSTALL_CONF" ]; then
    # shellcheck source=/dev/null
    source "$RMODUS_INSTALL_CONF"
fi

XSENS_WS_DIR="$WS_PATH/src/xsens_mti_driver"
RF2O_DIR="$WS_PATH/src/rf2o_laser_odometry"
SNAV_DIR="$WS_PATH/src/sw_nav_module"

read -r -a SW_NAV_DIRS_ARRAY <<< "$SW_NAV_SPARSE_DIRS"

echo ""
echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║  RMODUS — instalace ROS 2 ${ROS_DISTRO} + workspace                       ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo "  Konfig: ${RMODUS_INSTALL_CONF:-—} $([ -f "$RMODUS_INSTALL_CONF" ] && echo '(načteno)' || echo '(výchozí hodnoty)')"
echo "  sw-nav: FETCH=$FETCH_SW_NAV_MODULE  složky: ${SW_NAV_SPARSE_DIRS}"
echo "  Xsens:  FETCH=$FETCH_XSENS_DRIVER  xspublic=$BUILD_XSPUBLIC  udev=$INSTALL_XSENS_UDEV"
echo "  rf2o:   FETCH=$FETCH_RF2O  samostatná fáze buildu=$BUILD_RF2O_SEPARATE_PHASE"
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

    if [[ "$folder" == */* ]]; then
        git clone --depth 1 -b "$branch" "$url" "$target_dir"
        git -C "$target_dir" sparse-checkout init --no-cone
        git -C "$target_dir" sparse-checkout set "$folder"
    else
        git clone --depth 1 -b "$branch" --sparse "$url" "$target_dir"
        git -C "$target_dir" sparse-checkout set "$folder"
    fi
}

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
# [2] ZÁKLADNÍ APT
#-------------------------------------------------------------------------------
echo "┌──────────────────────────────────────────────────────────────────────────┐"
echo "│ [2] Apt: aktualizace + curl, git, build-essential, pip                    │"
echo "└──────────────────────────────────────────────────────────────────────────┘"
sudo apt update && sudo apt upgrade -y
sudo apt install -y \
    curl gnupg2 lsb-release python3-pip \
    git build-essential

#-------------------------------------------------------------------------------
# [3] ROS 2 JAZZY + rosdep
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
# [4] WORKSPACE — stažení zdrojáků
#-------------------------------------------------------------------------------
echo ""
echo "┌──────────────────────────────────────────────────────────────────────────┐"
echo "│ [4] Workspace $WS_PATH — klonování repozitářů                             │"
echo "└──────────────────────────────────────────────────────────────────────────┘"
mkdir -p "$WS_PATH/src"
cd "$WS_PATH"

if [ "${FETCH_SW_NAV_MODULE}" = 1 ]; then
    echo "  (4a) R-MODUS/sw-nav-module (větev $SW_NAV_BRANCH) → ${SW_NAV_SPARSE_DIRS}"
    sparse_clone_flat_multi \
        "https://github.com/R-MODUS/sw-nav-module.git" \
        "$SW_NAV_BRANCH" \
        "$SNAV_DIR" \
        "${SW_NAV_DIRS_ARRAY[@]}"
    if [ -d "$SNAV_DIR/.git" ]; then
        _fix_sparse=false
        for d in "${SW_NAV_DIRS_ARRAY[@]}"; do
            if [ ! -f "$SNAV_DIR/$d/package.xml" ]; then
                _fix_sparse=true
                break
            fi
        done
        if [ "$_fix_sparse" = true ]; then
            echo "  (4a-fix) Doplňuji sparse-checkout: ${SW_NAV_DIRS_ARRAY[*]}"
            git -C "$SNAV_DIR" sparse-checkout set "${SW_NAV_DIRS_ARRAY[@]}"
        fi
    fi
else
    echo "  (4a) sw-nav-module — přeskočeno (FETCH_SW_NAV_MODULE=0)"
fi

if [ "${FETCH_XSENS_DRIVER}" = 1 ]; then
    echo "  (4b) Xsens MTi ROS2 driver (větev ros2)"
    sparse_clone \
        "https://github.com/xsenssupport/Xsens_MTi_ROS_Driver_and_Ntrip_Client.git" \
        "ros2" \
        "$XSENS_WS_DIR" \
        "src/xsens_mti_ros2_driver/"
else
    echo "  (4b) Xsens driver — přeskočeno (FETCH_XSENS_DRIVER=0)"
fi

if [ "${FETCH_RF2O}" = 1 ]; then
    echo "  (4c) rf2o_laser_odometry (větev ros2)"
    if [ ! -d "$RF2O_DIR/.git" ]; then
        rm -rf "$RF2O_DIR"
        git clone --depth 1 -b ros2 https://github.com/MAPIRlab/rf2o_laser_odometry.git "$RF2O_DIR"
    fi
else
    echo "  (4c) rf2o — přeskočeno (FETCH_RF2O=0)"
fi

#-------------------------------------------------------------------------------
# [5] XSENS — xspublic (make)
#-------------------------------------------------------------------------------
echo ""
echo "┌──────────────────────────────────────────────────────────────────────────┐"
echo "│ [5] Xsens xspublic — make v lib/xspublic                                  │"
echo "└──────────────────────────────────────────────────────────────────────────┘"
XSPUBLIC_DIR="$XSENS_WS_DIR/src/xsens_mti_ros2_driver/lib/xspublic"
if [ "${FETCH_XSENS_DRIVER}" = 1 ] && [ "${BUILD_XSPUBLIC}" = 1 ]; then
    if [ -d "$XSPUBLIC_DIR" ]; then
        (cd "$XSPUBLIC_DIR" && make)
    else
        echo "         (xspublic nenalezen — přeskočeno)"
    fi
else
    echo "         (přeskočeno: FETCH_XSENS_DRIVER=$FETCH_XSENS_DRIVER, BUILD_XSPUBLIC=$BUILD_XSPUBLIC)"
fi

if [ -z "$(find "$WS_PATH/src" -name package.xml -print -quit 2>/dev/null)" ]; then
    echo "CHYBA: v $WS_PATH/src není žádný package.xml — zapněte alespoň jeden zdroj v conf." >&2
    exit 1
fi

#-------------------------------------------------------------------------------
# [6a] ROSDEP
#-------------------------------------------------------------------------------
echo ""
echo "┌──────────────────────────────────────────────────────────────────────────┐"
echo "│ [6a] rosdep install — systémové závislosti z package.xml ve src/          │"
echo "└──────────────────────────────────────────────────────────────────────────┘"
rosdep install --from-paths src --ignore-src -y --rosdistro "$ROS_DISTRO" --skip-keys cmake_modules

#-------------------------------------------------------------------------------
# [6b] / [6c] COLCON
#-------------------------------------------------------------------------------
export CMAKE_BUILD_PARALLEL_LEVEL="${CMAKE_BUILD_PARALLEL_LEVEL:-1}"
export MAKEFLAGS="${MAKEFLAGS:--j1}"

if [ "${FETCH_RF2O}" = 1 ] && [ "${BUILD_RF2O_SEPARATE_PHASE}" = 1 ]; then
    echo ""
    echo "┌──────────────────────────────────────────────────────────────────────────┐"
    echo "│ [6b] colcon build — balíčky ve workspace kromě rf2o_laser_odometry       │"
    echo "└──────────────────────────────────────────────────────────────────────────┘"
    colcon build --symlink-install --parallel-workers 1 --packages-skip rf2o_laser_odometry

    echo ""
    echo "┌──────────────────────────────────────────────────────────────────────────┐"
    echo "│ [6c] colcon build — pouze rf2o_laser_odometry (linker, šetření RAM)      │"
    echo "└──────────────────────────────────────────────────────────────────────────┘"
    colcon build --symlink-install --parallel-workers 1 --packages-select rf2o_laser_odometry \
        --cmake-args \
        '-DCMAKE_EXE_LINKER_FLAGS=-Wl,--no-keep-memory' \
        '-DCMAKE_SHARED_LINKER_FLAGS=-Wl,--no-keep-memory'
else
    echo ""
    echo "┌──────────────────────────────────────────────────────────────────────────┐"
    echo "│ [6b] colcon build — celý workspace (jedna fáze)                          │"
    echo "└──────────────────────────────────────────────────────────────────────────┘"
    colcon build --symlink-install --parallel-workers 1
fi

if [ ! -f "$WS_PATH/install/setup.bash" ]; then
    echo "CHYBA: chybí $WS_PATH/install/setup.bash — build nedoběhl." >&2
    exit 1
fi

#-------------------------------------------------------------------------------
# [7] BASH
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
# [8] SÉRIOVÉ PORTY
#-------------------------------------------------------------------------------
echo ""
echo "┌──────────────────────────────────────────────────────────────────────────┐"
echo "│ [8] Práva k /dev/ttyUSB*, /dev/ttyACM* — skupiny dialout (a plugdev)      │"
echo "└──────────────────────────────────────────────────────────────────────────┘"
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
# [9a] UDEV — Xsens
#-------------------------------------------------------------------------------
echo ""
echo "┌──────────────────────────────────────────────────────────────────────────┐"
echo "│ [9a] udev — pravidla pro Xsens MTi (99-xsens-mti.rules)                   │"
echo "└──────────────────────────────────────────────────────────────────────────┘"
if [ "${INSTALL_XSENS_UDEV}" = 1 ] && [ -d "$XSENS_WS_DIR/src/xsens_mti_ros2_driver/resources" ]; then
    sudo cp "$XSENS_WS_DIR/src/xsens_mti_ros2_driver/resources/99-xsens-mti.rules" /etc/udev/rules.d/
    sudo udevadm control --reload-rules && sudo udevadm trigger
    echo "         Pravidla zkopírována a udev znovu načten."
elif [ "${INSTALL_XSENS_UDEV}" != 1 ]; then
    echo "         Přeskočeno (INSTALL_XSENS_UDEV=0)."
else
    echo "         Adresář resources/ nenalezen — přeskočeno (chybí Xsens driver ve src?)."
fi

#-------------------------------------------------------------------------------
# [9b] SYSTEMD — služba rmodus
#-------------------------------------------------------------------------------
echo ""
echo "┌──────────────────────────────────────────────────────────────────────────┐"
echo "│ [9b] systemd — jednotka rmodus.service (enable)                          │"
echo "└──────────────────────────────────────────────────────────────────────────┘"
if [ "${ENABLE_SYSTEMD_RMODUS}" = 1 ] && [ -f "$DEPLOY_PATH/rmodus.service" ]; then
    sudo cp "$DEPLOY_PATH/rmodus.service" /etc/systemd/system/
    cp "$DEPLOY_PATH/rmodus_entrypoint.sh" "$HOME/"
    chmod +x "$HOME/rmodus_entrypoint.sh"
    sudo systemctl daemon-reload
    sudo systemctl enable rmodus.service
    echo "         Služba rmodus povolena (enable). Start: sudo systemctl start rmodus"
elif [ "${ENABLE_SYSTEMD_RMODUS}" != 1 ]; then
    echo "         Přeskočeno (ENABLE_SYSTEMD_RMODUS=0)."
else
    echo "         $DEPLOY_PATH/rmodus.service nenalezen."
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
echo ""
