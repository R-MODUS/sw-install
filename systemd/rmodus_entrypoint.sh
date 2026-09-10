#!/bin/bash
# Sablona v ~/rmodus/setup/systemd/; install.py doplni __PLACEHOLDERS__ na miste (jedina kopie, ne v ~/).
# Poznamka: NEpouzivej "set -u" pred source ROS setup.bash — ament promenne (AMENT_TRACE_*)
# nejsou vzdy nastavene a nounset jinak shodi systemd sluzbu.
set -eo pipefail

_CONFIGS="__CONFIGS_ROOT__"
_NETWORK_BIN="/usr/local/sbin/rmodus-network"
_CONFIG_BIN="/usr/local/sbin/rmodus-config"

# Resolve aktivni robot profil (profiles/ + active)
if [ -x "$_CONFIG_BIN" ]; then
    _CFG="$("$_CONFIG_BIN" --configs-root "$_CONFIGS" path --active)"
else
    _ACTIVE="$(tr -d '[:space:]' < "${_CONFIGS}/active" 2>/dev/null || true)"
    _CFG="${_CONFIGS}/profiles/${_ACTIVE}.yaml"
fi

# boot.rmodus=false → tiché ukončení
if [ -x "$_NETWORK_BIN" ]; then
    set +e
    "$_NETWORK_BIN" boot-check rmodus "$_CFG"
    _boot_rc=$?
    set -e
    if [ "$_boot_rc" -eq 10 ]; then
        exit 0
    fi
    if [ "$_boot_rc" -ne 0 ]; then
        echo "rmodus: boot-check selhal (rc=$_boot_rc)" >&2
        exit "$_boot_rc"
    fi
fi

if [ ! -f "$_CFG" ]; then
    echo "rmodus: chybi aktivni profil ($_CFG) — rmodus-config activate <name>" >&2
    exit 1
fi

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

exec ros2 launch rmodus_bringup rmodus.launch.py "robot_yaml:=${_CFG}"
