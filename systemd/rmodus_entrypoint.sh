#!/bin/bash
# Sablona v ~/rmodus/setup/systemd/; install.py doplni __PLACEHOLDERS__ na miste (jedina kopie, ne v ~/).
# Poznamka: NEpouzivej "set -u" pred source ROS setup.bash — ament promenne (AMENT_TRACE_*)
# nejsou vzdy nastavene a nounset jinak shodi systemd sluzbu.
set -eo pipefail

_CONFIGS="__CONFIGS_ROOT__"
_NETWORK_BIN="/usr/local/sbin/rmodus-network"

# Aktivní profil: configs/active → configs/profiles/<name>.yaml|.yml
_ACTIVE="$(head -n1 "${_CONFIGS}/active" 2>/dev/null | sed 's/#.*//' | tr -d '[:space:]' || true)"
if [ -z "$_ACTIVE" ]; then
    echo "rmodus: chybi ukazatel ${_CONFIGS}/active (jmeno profilu)" >&2
    exit 1
fi

_CFG=""
for _ext in yaml yml; do
    if [ -f "${_CONFIGS}/profiles/${_ACTIVE}.${_ext}" ]; then
        _CFG="${_CONFIGS}/profiles/${_ACTIVE}.${_ext}"
        break
    fi
done

# boot.rmodus=false → tiché ukončení
if [ -x "$_NETWORK_BIN" ] && [ -n "$_CFG" ]; then
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

if [ -z "$_CFG" ] || [ ! -f "$_CFG" ]; then
    echo "rmodus: aktivni profil '${_ACTIVE}' neexistuje v ${_CONFIGS}/profiles/ (*.yaml|*.yml)" >&2
    echo "rmodus: nastav jmeno v ${_CONFIGS}/active nebo vytvor profil (web UI / rmodus_config)" >&2
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
