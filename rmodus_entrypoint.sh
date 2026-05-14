#!/bin/bash
set -euo pipefail
# Placeholdery nahradí install.py při kopii do domovského adresáře.
_RENV="__DEPLOY_PATH__/rmodus_ros.env"
if [ -f "$_RENV" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$_RENV"
    set +a
fi

source "/opt/ros/__ROS_DISTRO__/setup.bash"
source "__WS_PATH__/install/setup.bash"

# Upravte název launch souboru, pokud se liší od rmodus_main.launch.py
#ros2 launch rmodus_hw rmodus_main.launch.py
