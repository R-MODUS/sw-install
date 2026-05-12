#!/bin/bash
set -e

# --- 1. KONFIGURACE ---
WS_PATH="$HOME/rmodus_ws"
DEPLOY_PATH="$HOME/rmodus_setup"
ROS_DISTRO="jazzy"

echo "===================================================="
echo "START INSTALACE FRAMEWORKU RMODUS (ROS 2 $ROS_DISTRO)"
echo "===================================================="

# --- 2. DEFINICE FUNKCE PRO SPARSE CHECKOUT ---
sparse_clone() {
    local url=$1
    local branch=$2
    local target_dir=$3
    local folder_to_keep=$4

    echo "--> Selektivně stahuji: $folder_to_keep"

    mkdir -p "$target_dir" && cd "$target_dir"

    if [ ! -d ".git" ]; then
        git init
        git remote add origin "$url"
        git config core.sparseCheckout true
        echo "$folder_to_keep" >> .git/info/sparse-checkout
    fi

    git pull --depth 1 origin "$branch"
    cd "$WS_PATH"
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
# vcstool/colcon: z packages.ros.org (na čistém Noble často chybí jen v ubuntu-ports).
sudo apt install -y \
    ros-$ROS_DISTRO-ros-base \
    ros-$ROS_DISTRO-dev-tools \
    python3-vcstool \
    python3-colcon-common-extensions

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

# A: sw-nav-module — pouze balíček rmodus_hw (viz https://github.com/R-MODUS/sw-nav-module/tree/main/rmodus_hw)
sparse_clone \
    "https://github.com/R-MODUS/sw-nav-module.git" \
    "main" \
    "$WS_PATH/src/sw_nav_module" \
    "rmodus_hw/"

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

# --- 7. INSTALACE ZÁVISLOSTÍ A BUILD ---
rosdep install --from-paths src --ignore-src -y --rosdistro "$ROS_DISTRO"

# Omezení na 2 workery kvůli 4GB RAM na Pi 4
colcon build --symlink-install --parallel-workers 2

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
echo "INSTALACE DOKONČENA. Restartujte Pi."
echo "===================================================="
