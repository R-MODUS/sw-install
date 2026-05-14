#!/usr/bin/env python3
"""
R-MODUS — instalace ROS 2 Jazzy + workspace na Raspberry Pi (Ubuntu).

"""
from __future__ import annotations

import getpass
import io
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


def _force_line_buffered_stdio() -> None:
    """Print jde hned na konzoli i při spuštění z roury nebo bez plného TTY."""
    for stream in (sys.stdout, sys.stderr):
        if stream is None or not hasattr(stream, "reconfigure"):
            continue
        try:
            stream.reconfigure(line_buffering=True)
        except (OSError, ValueError, AttributeError, io.UnsupportedOperation):
            pass


_force_line_buffered_stdio()


DEFAULTS: dict[str, str] = {
    "ROS_DISTRO": "jazzy",
    "WS_PATH": str(Path.home() / "rmodus_ws"),
    "DEPLOY_PATH": str(Path.home() / "rmodus_setup"),
    "FETCH_SW_NAV_MODULE": "1",
    "SW_NAV_SPARSE_DIRS": "rmodus_hw rmodus_web rmodus_interface rmodus_description rmodus_autonomy",
    "SW_NAV_BRANCH": "main",
    "FETCH_XSENS_DRIVER": "0",
    "BUILD_XSPUBLIC": "1",
    "INSTALL_XSENS_UDEV": "1",
    "FETCH_RF2O": "0",
    "BUILD_RF2O_SEPARATE_PHASE": "1",
    "ENABLE_SYSTEMD_RMODUS": "1",
    "INSTALL_RMODUS_ROSDEP_RULES": "1",
    "RMODUS_ROSDEP_YAML_URL": "",
    "INSTALL_RMODUS_HW_PIP": "1",
}


def _banner(title: str) -> None:
    """ASCII jen kvuli SSH klientum bez UTF-8."""
    w = 74
    print("+" + "-" * w + "+")
    print("| " + (title[: w - 2]).ljust(w - 2) + " |")
    print("+" + "-" * w + "+")


def _run(
    cmd: list[str] | str,
    *,
    check: bool = True,
    env: dict[str, str] | None = None,
    cwd: Path | None = None,
) -> subprocess.CompletedProcess[str]:
    if isinstance(cmd, str):
        return subprocess.run(cmd, shell=True, check=check, cwd=cwd, env=env, text=True)
    return subprocess.run(cmd, check=check, cwd=cwd, env=env, text=True)


def _sudo(cmd: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
    return _run(["sudo", *cmd], **kwargs)  # type: ignore[arg-type]


def _sudo_write(path: str, content: str) -> None:
    subprocess.run(["sudo", "tee", path], input=content, text=True, check=True)


# Jeden apt-get install: libbz2-1.0 + bzip2 spolecne (nesoulad 5.1 vs 5.1build0.1 na ports).
_BASE_DEB_PKGS: tuple[str, ...] = (
    "libbz2-1.0",
    "bzip2",
    "ca-certificates",
    "curl",
    "gnupg2",
    "lsb-release",
    "python3-pip",
    "git",
    "build-essential",
)


def _apt(args: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    """apt-get pod sudo; DEBIAN_FRONTEND se bez 'sudo env' casto nepreda do apt."""
    return _run(
        [
            "sudo",
            "env",
            "DEBIAN_FRONTEND=noninteractive",
            "NEEDRESTART_MODE=a",
            "apt-get",
            "-o",
            "DPkg::Use-Pty=0",
            *args,
        ],
        check=check,
    )


def _ubuntu_deb_mirror() -> str:
    """Oficialni mirror: ports pro ARM atd., archive pro amd64."""
    a = _dpkg_arch()
    if a in ("arm64", "armhf", "riscv64", "ppc64el", "s390x", "mips64el"):
        return "http://ports.ubuntu.com/ubuntu-ports"
    return "http://archive.ubuntu.com/ubuntu"


def _apt_sources_text_blob() -> str:
    parts: list[str] = []
    root = Path("/etc/apt/sources.list")
    if root.is_file():
        try:
            parts.append(root.read_text(encoding="utf-8", errors="replace"))
        except OSError:
            pass
    d = Path("/etc/apt/sources.list.d")
    if d.is_dir():
        for p in sorted(d.iterdir()):
            if p.suffix in (".list", ".sources") or p.name == "ubuntu.sources":
                try:
                    parts.append(p.read_text(encoding="utf-8", errors="replace"))
                except OSError:
                    pass
    return "\n".join(parts)


def _apt_sources_have_updates_suite(codename: str) -> bool:
    return f"{codename}-updates" in _apt_sources_text_blob()


def _apt_write_updates_list(codename: str) -> None:
    uri = _ubuntu_deb_mirror()
    body = (
        "# Added by RMODUS install.py: pocket *-updates (minimalni image casto ma jen +security; "
        "bez updates byva nesoulad bzip2 vs libbz2).\n"
        f"deb {uri} {codename}-updates main restricted universe multiverse\n"
    )
    _sudo_write("/etc/apt/sources.list.d/rmodus-ubuntu-updates.list", body)


def _apt_install_base_toolchain() -> None:
    _apt(["-f", "-y", "install"], check=False)
    _run(["sudo", "dpkg", "--configure", "-a"], check=False)
    variants: tuple[list[str], ...] = (
        ["install", "-y", *_BASE_DEB_PKGS],
        ["install", "-y", "--allow-downgrades", *_BASE_DEB_PKGS],
    )
    last_err: subprocess.CalledProcessError | None = None

    def try_variants(*, warn_on_first_round: bool) -> bool:
        nonlocal last_err
        for i, tail in enumerate(variants):
            try:
                _apt(tail, check=True)
                return True
            except subprocess.CalledProcessError as e:
                last_err = e
                if warn_on_first_round and i == 0:
                    print(
                        "  VAROVANI: apt install selhal (casto nesoulad libbz2/bzip2); "
                        "opakuji s --allow-downgrades...",
                        file=sys.stderr,
                    )
        return False

    if try_variants(warn_on_first_round=True):
        return

    osr = _read_os_release()
    codename = (osr.get("VERSION_CODENAME") or "").strip()
    if codename and osr.get("ID") == "ubuntu" and not _apt_sources_have_updates_suite(codename):
        print(
            f"  INFO: v apt chybi pocket {codename}-updates; pridavam "
            "rmodus-ubuntu-updates.list a znovu apt-get update.",
            file=sys.stderr,
        )
        _apt_write_updates_list(codename)
        _apt(["update"], check=True)
        if try_variants(warn_on_first_round=False):
            return

    assert last_err is not None
    print(
        "CHYBA: zakladni apt balicky nelze nainstalovat. Diagnostika: "
        "sudo apt-get update && apt-cache policy libbz2-1.0 bzip2 build-essential",
        file=sys.stderr,
    )
    raise last_err


def _read_os_release() -> dict[str, str]:
    out: dict[str, str] = {}
    p = Path("/etc/os-release")
    if not p.is_file():
        return out
    for line in p.read_text(encoding="utf-8").splitlines():
        if "=" in line and not line.strip().startswith("#"):
            k, _, v = line.partition("=")
            out[k.strip()] = v.strip().strip('"')
    return out


def _dpkg_arch() -> str:
    return subprocess.check_output(["dpkg", "--print-architecture"], text=True).strip()


def _as_bool(s: str) -> bool:
    return str(s).strip().lower() in ("1", "true", "yes", "on", "y")


def _sparse_clone_flat_multi(url: str, branch: str, target_dir: Path, dirs: list[str]) -> None:
    print(f"    [git sparse] {' '.join(dirs)} → {target_dir.name}")
    if (target_dir / ".git").is_dir():
        print(f"         (složka už existuje — přeskočeno; pro čistý stav smažte {target_dir})")
        return
    target_dir.parent.mkdir(parents=True, exist_ok=True)
    if target_dir.exists():
        shutil.rmtree(target_dir)
    _run(["git", "clone", "--depth", "1", "-b", branch, "--sparse", url, str(target_dir)], check=True)
    _run(["git", "-C", str(target_dir), "sparse-checkout", "set", *dirs], check=True)


def _sparse_clone_fix_missing(snav: Path, dirs: list[str]) -> None:
    if not (snav / ".git").is_dir():
        return
    if any(not (snav / d / "package.xml").is_file() for d in dirs):
        print(f"  (4a-fix) Doplňuji sparse-checkout: {' '.join(dirs)}")
        _run(["git", "-C", str(snav), "sparse-checkout", "set", *dirs], check=True)


def _sparse_clone_nested_folder(url: str, branch: str, target_dir: Path, folder: str) -> None:
    folder = folder.rstrip("/")
    print(f"    [git sparse] {folder}/ → {target_dir.name}")
    if (target_dir / ".git").is_dir():
        print(f"         (složka už existuje — přeskočeno; pro čistý stav smažte {target_dir})")
        return
    target_dir.parent.mkdir(parents=True, exist_ok=True)
    if target_dir.exists():
        shutil.rmtree(target_dir)
    if "/" in folder:
        _run(["git", "clone", "--depth", "1", "-b", branch, url, str(target_dir)], check=True)
        _run(["git", "-C", str(target_dir), "sparse-checkout", "init", "--no-cone"], check=True)
        _run(["git", "-C", str(target_dir), "sparse-checkout", "set", folder], check=True)
    else:
        _run(["git", "clone", "--depth", "1", "-b", branch, "--sparse", url, str(target_dir)], check=True)
        _run(["git", "-C", str(target_dir), "sparse-checkout", "set", folder], check=True)


def _bash_script(script: str, *, cwd: Path | None = None, env: dict[str, str] | None = None) -> None:
    merged = os.environ.copy()
    if env:
        merged.update(env)
    _run(["/bin/bash", "-lc", script], check=True, cwd=cwd, env=merged)


def _find_package_xml_under(src: Path) -> bool:
    return any(src.rglob("package.xml"))


def main() -> int:
    c = dict(DEFAULTS)

    ros_distro = c["ROS_DISTRO"]
    ws_path = Path(c["WS_PATH"]).expanduser()
    deploy_path = Path(c["DEPLOY_PATH"]).expanduser()
    xsens_ws_dir = ws_path / "src" / "xsens_mti_driver"
    rf2o_dir = ws_path / "src" / "rf2o_laser_odometry"
    snav_dir = ws_path / "src" / "sw_nav_module"
    sw_nav_dirs = c["SW_NAV_SPARSE_DIRS"].split()

    user = getpass.getuser()
    home = Path.home()

    print("")
    _banner(f"RMODUS -- instalace ROS 2 {ros_distro} + workspace")
    print(f"  sw-nav: FETCH={c['FETCH_SW_NAV_MODULE']}  slozky: {c['SW_NAV_SPARSE_DIRS']}")
    print(
        f"  Xsens:  FETCH={c['FETCH_XSENS_DRIVER']}  xspublic={c['BUILD_XSPUBLIC']}  udev={c['INSTALL_XSENS_UDEV']}"
    )
    print(
        f"  rf2o:   FETCH={c['FETCH_RF2O']}  samostatna faze buildu={c['BUILD_RF2O_SEPARATE_PHASE']}"
    )
    print(f"  rosdep: vlastni R-MODUS pravidla={c['INSTALL_RMODUS_ROSDEP_RULES']}")
    print(f"  pip rmodus_hw: {c['INSTALL_RMODUS_HW_PIP']}")
    print("")

    # [2]
    _banner("[2] Apt: aktualizace + curl, git, build-essential, pip (+ libbz2/bzip2 v jedne transakci)")
    _apt(["update"], check=True)
    _apt(["-y", "upgrade"], check=True)
    _apt_install_base_toolchain()

    # [3]
    print("")
    _banner(f"[3] ROS 2 {ros_distro}: repozitář packages.ros.org, ros-base, ros-dev-tools")
    os_release = _read_os_release()
    ubuntu_codename = os_release.get("VERSION_CODENAME", "")
    if not ubuntu_codename:
        print("CHYBA: nelze zjistit VERSION_CODENAME z /etc/os-release", file=sys.stderr)
        return 1

    _sudo(
        [
            "curl",
            "-sSL",
            "https://raw.githubusercontent.com/ros/rosdistro/master/ros.key",
            "-o",
            "/usr/share/keyrings/ros-archive-keyring.gpg",
        ],
        check=True,
    )
    deb_line = (
        f"deb [arch={_dpkg_arch()} signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] "
        f"http://packages.ros.org/ros2/ubuntu {ubuntu_codename} main\n"
    )
    _sudo_write("/etc/apt/sources.list.d/ros2.list", deb_line)
    _apt(["update"], check=True)
    _apt(["install", "-y", f"ros-{ros_distro}-ros-base", "ros-dev-tools"], check=True)

    _bash_script(f"source /opt/ros/{ros_distro}/setup.bash && true")

    rosdep_sources = Path("/etc/ros/rosdep/sources.list.d")
    if not rosdep_sources.is_dir():
        _sudo(["rosdep", "init"], check=True)
    _run(["rosdep", "update"], check=True)

    # [4]
    print("")
    _banner(f"[4] Workspace {ws_path} — klonování repozitářů")
    ws_path.mkdir(parents=True, exist_ok=True)
    (ws_path / "src").mkdir(parents=True, exist_ok=True)

    if _as_bool(c["FETCH_SW_NAV_MODULE"]):
        print(f"  (4a) R-MODUS/sw-nav-module (větev {c['SW_NAV_BRANCH']}) → {c['SW_NAV_SPARSE_DIRS']}")
        _sparse_clone_flat_multi(
            "https://github.com/R-MODUS/sw-nav-module.git",
            c["SW_NAV_BRANCH"],
            snav_dir,
            sw_nav_dirs,
        )
        _sparse_clone_fix_missing(snav_dir, sw_nav_dirs)
    else:
        print("  (4a) sw-nav-module — přeskočeno (FETCH_SW_NAV_MODULE=0)")

    if _as_bool(c["FETCH_XSENS_DRIVER"]):
        print("  (4b) Xsens MTi ROS2 driver (větev ros2)")
        _sparse_clone_nested_folder(
            "https://github.com/xsenssupport/Xsens_MTi_ROS_Driver_and_Ntrip_Client.git",
            "ros2",
            xsens_ws_dir,
            "src/xsens_mti_ros2_driver/",
        )
    else:
        print("  (4b) Xsens driver — přeskočeno (FETCH_XSENS_DRIVER=0)")

    if _as_bool(c["FETCH_RF2O"]):
        print("  (4c) rf2o_laser_odometry (větev ros2)")
        if not (rf2o_dir / ".git").is_dir():
            if rf2o_dir.exists():
                shutil.rmtree(rf2o_dir)
            rf2o_dir.parent.mkdir(parents=True, exist_ok=True)
            _run(
                [
                    "git",
                    "clone",
                    "--depth",
                    "1",
                    "-b",
                    "ros2",
                    "https://github.com/MAPIRlab/rf2o_laser_odometry.git",
                    str(rf2o_dir),
                ],
                check=True,
            )
    else:
        print("  (4c) rf2o — přeskočeno (FETCH_RF2O=0)")

    # [5]
    print("")
    _banner("[5] Xsens xspublic — make v lib/xspublic")
    xspublic_dir = xsens_ws_dir / "src" / "xsens_mti_ros2_driver" / "lib" / "xspublic"
    if _as_bool(c["FETCH_XSENS_DRIVER"]) and _as_bool(c["BUILD_XSPUBLIC"]):
        if xspublic_dir.is_dir():
            _run(["make"], cwd=xspublic_dir, check=True)
        else:
            print("         (xspublic nenalezen — přeskočeno)")
    else:
        print(
            f"         (přeskočeno: FETCH_XSENS_DRIVER={c['FETCH_XSENS_DRIVER']}, BUILD_XSPUBLIC={c['BUILD_XSPUBLIC']})"
        )

    if not _find_package_xml_under(ws_path / "src"):
        print(
            f"CHYBA: v {ws_path / 'src'} není žádný package.xml — zapněte alespoň jeden zdroj v conf.",
            file=sys.stderr,
        )
        return 1

    # [6a]
    print("")
    _banner("[6a] rosdep — závislosti z package.xml ve src/")
    if _as_bool(c["INSTALL_RMODUS_ROSDEP_RULES"]):
        print("  (6a0) R-MODUS/sw-nav-module — rosdep/rmodus_custom.yaml → /etc/ros/rosdep/")
        yaml_url = (c.get("RMODUS_ROSDEP_YAML_URL") or "").strip()
        if not yaml_url:
            yaml_url = (
                f"https://raw.githubusercontent.com/R-MODUS/sw-nav-module/"
                f"{c['SW_NAV_BRANCH']}/rosdep/rmodus_custom.yaml"
            )
        tmp = Path("/etc/ros/rosdep/rmodus_custom.yaml.new")
        try:
            _sudo(["curl", "-fsSL", yaml_url, "-o", str(tmp)], check=True)
            _sudo(["mv", str(tmp), "/etc/ros/rosdep/rmodus_custom.yaml"], check=True)
            _sudo_write(
                "/etc/ros/rosdep/sources.list.d/20-rmodus-custom.list",
                "yaml file:///etc/ros/rosdep/rmodus_custom.yaml\n",
            )
            _run(["rosdep", "update"], check=True)
            print(f"         Zdroj: {yaml_url}")
        except subprocess.CalledProcessError:
            print(
                f"         VAROVÁNÍ: nelze stáhnout {yaml_url} — pokračuji bez vlastních rosdep klíčů R-MODUS",
                file=sys.stderr,
            )
            _sudo(["rm", "-f", str(tmp)], check=False)
    else:
        print("  (6a0) vlastní rosdep pravidla R-MODUS — přeskočeno (INSTALL_RMODUS_ROSDEP_RULES=0)")

    print("  (6a1) rosdep install — systémové (a pip) závislosti z package.xml")
    _run(
        [
            "rosdep",
            "install",
            "--from-paths",
            "src",
            "--ignore-src",
            "-y",
            "--rosdistro",
            ros_distro,
            "--skip-keys",
            "cmake_modules",
        ],
        cwd=ws_path,
        check=True,
    )

    rhw_pkg = snav_dir / "rmodus_hw" / "package.xml"
    rhw_req = snav_dir / "rmodus_hw" / "requirements-pip.txt"
    if _as_bool(c["INSTALL_RMODUS_HW_PIP"]) and rhw_pkg.is_file():
        print("  (6a2) pip install — rmodus_hw (PEP 668: --user --break-system-packages)")
        pip_base = [
            sys.executable,
            "-m",
            "pip",
            "install",
            "--user",
            "--upgrade",
            "--break-system-packages",
        ]
        if rhw_req.is_file():
            _run([*pip_base, "-r", str(rhw_req)], check=True)
        else:
            print("         (chybí requirements-pip.txt — záložní seznam)")
            _run(
                [
                    *pip_base,
                    "Adafruit-Blinka",
                    "RPi.GPIO",
                    "adafruit-circuitpython-mcp230xx",
                    "adafruit-circuitpython-ads1x15",
                    "spidev",
                    "pmw3901",
                    "adafruit-circuitpython-ssd1306",
                ],
                check=True,
            )
    elif not _as_bool(c["INSTALL_RMODUS_HW_PIP"]):
        print("  (6a2) pip rmodus_hw — přeskočeno (INSTALL_RMODUS_HW_PIP=0)")
    else:
        print(f"  (6a2) pip rmodus_hw — přeskočeno (chybí {rhw_pkg})")

    # [6b]/[6c]
    build_env = os.environ.copy()
    build_env.setdefault("CMAKE_BUILD_PARALLEL_LEVEL", "1")
    build_env.setdefault("MAKEFLAGS", "-j1")

    if _as_bool(c["FETCH_RF2O"]) and _as_bool(c["BUILD_RF2O_SEPARATE_PHASE"]):
        print("")
        _banner("[6b] colcon build — balíčky ve workspace kromě rf2o_laser_odometry")
        _bash_script(
            f"source /opt/ros/{ros_distro}/setup.bash && "
            "colcon build --symlink-install --parallel-workers 1 --packages-skip rf2o_laser_odometry",
            cwd=ws_path,
            env=build_env,
        )
        print("")
        _banner("[6c] colcon build — pouze rf2o_laser_odometry (linker, šetření RAM)")
        _bash_script(
            f"source /opt/ros/{ros_distro}/setup.bash && "
            "colcon build --symlink-install --parallel-workers 1 --packages-select rf2o_laser_odometry "
            "--cmake-args "
            "'-DCMAKE_EXE_LINKER_FLAGS=-Wl,--no-keep-memory' "
            "'-DCMAKE_SHARED_LINKER_FLAGS=-Wl,--no-keep-memory'",
            cwd=ws_path,
            env=build_env,
        )
    else:
        print("")
        _banner("[6b] colcon build — celý workspace (jedna fáze)")
        _bash_script(
            f"source /opt/ros/{ros_distro}/setup.bash && colcon build --symlink-install --parallel-workers 1",
            cwd=ws_path,
            env=build_env,
        )

    if not (ws_path / "install" / "setup.bash").is_file():
        print(f"CHYBA: chybí {ws_path / 'install' / 'setup.bash'} — build nedoběhl.", file=sys.stderr)
        return 1

    # [7]
    print("")
    _banner("[7] ~/.bashrc — source /opt/ros a install/setup.bash")
    bashrc = home / ".bashrc"
    marker = f"/opt/ros/{ros_distro}/setup.bash"
    ros_env = deploy_path / "rmodus_ros.env"
    if bashrc.is_file() and Path(f"/opt/ros/{ros_distro}/setup.bash").is_file():
        text = bashrc.read_text(encoding="utf-8", errors="replace")
        if marker not in text:
            block = (
                "\n# --- RMODUS (přidáno install.py) ---\n"
                f'test -f "{ros_env}" && {{ set -a; source "{ros_env}"; set +a; }}\n'
                f"source /opt/ros/{ros_distro}/setup.bash\n"
                f'test -f "{ws_path}/install/setup.bash" && source "{ws_path}/install/setup.bash"\n'
            )
            with bashrc.open("a", encoding="utf-8") as f:
                f.write(block)
            print("         Řádky přidány do ~/.bashrc")
        else:
            print("         ~/.bashrc už obsahuje source pro ROS — beze změny")

    # [8]
    print("")
    _banner("[8] Práva k /dev/ttyUSB*, /dev/ttyACM* — skupiny dialout (a plugdev)")
    _sudo(["usermod", "-aG", "dialout", user], check=True)
    plugdev = subprocess.run(["getent", "group", "plugdev"], capture_output=True).returncode == 0
    if plugdev:
        _sudo(["usermod", "-aG", "plugdev", user], check=True)
        print(f"         Uživatel {user} přidán do: dialout, plugdev")
    else:
        print(f"         Uživatel {user} přidán do: dialout (skupina plugdev na systému není)")
    print("         → Skupiny platí po novém přihlášení nebo: newgrp dialout")
    print("         → LiDAR musí být připojený; port nemusí být ttyUSB0 (viz ls níže).")

    # [9a]
    print("")
    _banner("[9a] udev — pravidla pro Xsens MTi (99-xsens-mti.rules)")
    udev_src = xsens_ws_dir / "src" / "xsens_mti_ros2_driver" / "resources"
    if _as_bool(c["INSTALL_XSENS_UDEV"]) and udev_src.is_dir():
        rules = udev_src / "99-xsens-mti.rules"
        if rules.is_file():
            _sudo(["cp", str(rules), "/etc/udev/rules.d/"], check=True)
            _sudo(["udevadm", "control", "--reload-rules"], check=True)
            _sudo(["udevadm", "trigger"], check=True)
            print("         Pravidla zkopírována a udev znovu načten.")
        else:
            print("         Soubor 99-xsens-mti.rules nenalezen — přeskočeno.")
    elif not _as_bool(c["INSTALL_XSENS_UDEV"]):
        print("         Přeskočeno (INSTALL_XSENS_UDEV=0).")
    else:
        print("         Adresář resources/ nenalezen — přeskočeno (chybí Xsens driver ve src?).")

    # [9b]
    print("")
    _banner("[9b] systemd — jednotka rmodus.service (enable)")
    svc_src = deploy_path / "rmodus.service"
    ep_tpl = deploy_path / "rmodus_entrypoint.sh"
    if _as_bool(c["ENABLE_SYSTEMD_RMODUS"]) and svc_src.is_file() and ep_tpl.is_file():
        ep_body = ep_tpl.read_text(encoding="utf-8")
        ep_body = ep_body.replace("__DEPLOY_PATH__", str(deploy_path.resolve()))
        ep_body = ep_body.replace("__ROS_DISTRO__", ros_distro)
        ep_body = ep_body.replace("__WS_PATH__", str(ws_path.resolve()))
        entry_dst = home / "rmodus_entrypoint.sh"
        entry_dst.write_text(ep_body, encoding="utf-8")
        os.chmod(entry_dst, 0o755)

        svc_body = svc_src.read_text(encoding="utf-8")
        svc_body = svc_body.replace("__SERVICE_USER__", user)
        svc_body = svc_body.replace("__ENTRYPOINT__", str(entry_dst.resolve()))
        _sudo_write("/etc/systemd/system/rmodus.service", svc_body)

        _sudo(["systemctl", "daemon-reload"], check=True)
        _sudo(["systemctl", "enable", "rmodus.service"], check=True)
        print("         Služba rmodus povolena (enable). Start: sudo systemctl start rmodus")
    elif not _as_bool(c["ENABLE_SYSTEMD_RMODUS"]):
        print("         Přeskočeno (ENABLE_SYSTEMD_RMODUS=0).")
    else:
        print(f"         Chybí {svc_src} nebo {ep_tpl} v {deploy_path}.")

    # [10]
    print("")
    _banner("HOTOVE")
    print("  * Obnovte skupiny:  newgrp dialout   NEBO   odhlaseni / restart Pi")
    print("  * ROS v shellu:     source ~/.bashrc")
    print("  * Overeni:          ros2 doctor")
    print(f"  * ROS domena / RMW: {ros_env}")
    print("  * Seriove porty:    ls -l /dev/ttyUSB* /dev/ttyACM* 2>/dev/null || true")
    print("")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as e:
        print(f"CHYBA: příkaz selhal (exit {e.returncode}): {e.cmd}", file=sys.stderr)
        raise SystemExit(e.returncode)
