#!/bin/bash
# Sablona v ~/rmodus/setup/systemd/; install.py doplni __PLACEHOLDERS__ na miste (jedina kopie, ne v ~/).
# Poznamka: NEpouzivej "set -u" pred source ROS setup.bash — ament promenne (AMENT_TRACE_*)
# nejsou vzdy nastavene a nounset jinak shodi systemd sluzbu.
set -eo pipefail

_RENV="__DEPLOY_PATH__/systemd/rmodus_ros.env"
if [ -f "$_RENV" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$_RENV"
    set +a
fi

# shellcheck source=/dev/null
source "/opt/ros/__ROS_DISTRO__/setup.bash"
# shellcheck source=/dev/null
source "__WS_PATH__/install/setup.bash"

# Po bootu: web UI (rmodus_web). Pozdeji: rmodus_bringup robot.launch.py mode:=hw
exec ros2 launch rmodus_web web.launch.py
