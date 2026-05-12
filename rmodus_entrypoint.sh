#!/bin/bash
set -euo pipefail
source /opt/ros/jazzy/setup.bash
source /home/admin/rmodus_ws/install/setup.bash

# Upravte název launch souboru, pokud se liší od rmodus_main.launch.py
#ros2 launch rmodus_hw rmodus_main.launch.py