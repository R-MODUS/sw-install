#!/bin/bash
set -euo pipefail
# Sablona v ~/rmodus/setup/; install.py doplni __PLACEHOLDERS__ na miste (jedina kopie, ne v ~/).
_RENV="__DEPLOY_PATH__/rmodus_ros.env"
if [ -f "$_RENV" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$_RENV"
    set +a
fi

source "/opt/ros/__ROS_DISTRO__/setup.bash"
source "__WS_PATH__/install/setup.bash"

# Upravte nazev launch souboru, pokud se lisi od rmodus_main.launch.py
#ros2 launch rmodus_hw rmodus_main.launch.py
