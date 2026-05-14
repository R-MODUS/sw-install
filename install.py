#!/usr/bin/env python3
"""
R-MODUS: instalace ROS 2 Jazzy + workspace na Raspberry Pi (Ubuntu).

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
    """Print jde hned na konzoli i pri spusteni z roury nebo bez plneho TTY."""
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
    "SW_NAV_SPARSE_DIRS": "rmodus_hw rmodus_web rmodus_interface rmodus_description", #rmodus_autonomy
    "SW_NAV_BRANCH": "dev",
    "FETCH_XSENS_DRIVER": "0",
    "BUILD_XSPUBLIC": "1",
    "INSTALL_XSENS_UDEV": "1",
    "FETCH_RF2O": "0",
    "BUILD_RF2O_SEPARATE_PHASE": "1",
    "ENABLE_SYSTEMD_RMODUS": "1",
    "INSTALL_RMODUS_ROSDEP_RULES": "1",
    "RMODUS_ROSDEP_YAML_URL": "",
    "INSTALL_RMODUS_HW_PIP": "1",
    "SWAP_ENABLE": "1",
    "SWAP_SIZE_MB": "4096",
    "SWAP_PATH": "/swapfile",
}


def load_install_conf(path: Path) -> dict[str, str]:
    cfg = dict(DEFAULTS)
    if not path.is_file():
        return cfg
    key_re = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$")
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        m = key_re.match(line)
        if not m:
            continue
        key, val = m.group(1), m.group(2).strip()
        if (val.startswith('"') and val.endswith('"')) or (val.startswith("'") and val.endswith("'")):
            val = val[1:-1]
        cfg[key] = val
    return cfg


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
    print(f"    [git sparse] {' '.join(dirs)} -> {target_dir.name}")
    if (target_dir / ".git").is_dir():
        print(f"         (slozka uz existuje - preskoceno; pro cisty stav smazte {target_dir})")
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
        print(f"  (4a-fix) doplnuji sparse-checkout: {' '.join(dirs)}")
        _run(["git", "-C", str(snav), "sparse-checkout", "set", *dirs], check=True)


def _sparse_clone_nested_folder(url: str, branch: str, target_dir: Path, folder: str) -> None:
    folder = folder.rstrip("/")
    print(f"    [git sparse] {folder}/ -> {target_dir.name}")
    if (target_dir / ".git").is_dir():
        print(f"         (slozka uz existuje - preskoceno; pro cisty stav smazte {target_dir})")
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


def _rmodus_pip_requirement_files(ws_src: Path) -> list[Path]:
    """requirements-pip.txt u kazdeho ROS baliku rmodus_* (slozka s package.xml), bez duplicit."""
    out: list[Path] = []
    seen: set[Path] = set()
    if not ws_src.is_dir():
        return out
    for pkg_xml in ws_src.rglob("package.xml"):
        pkg_dir = pkg_xml.parent
        if not pkg_dir.name.startswith("rmodus_"):
            continue
        req = pkg_dir / "requirements-pip.txt"
        if not req.is_file():
            continue
        key = req.resolve()
        if key in seen:
            continue
        seen.add(key)
        out.append(req)
    return sorted(out, key=lambda p: p.as_posix().lower())


def _swapfile_exists(sp: str) -> bool:
    return subprocess.run(["sudo", "test", "-f", sp], capture_output=True).returncode == 0


def _swapfile_size_bytes(sp: str) -> int | None:
    r = subprocess.run(["sudo", "stat", "-c%s", sp], capture_output=True, text=True)
    if r.returncode != 0:
        return None
    try:
        return int(r.stdout.strip())
    except ValueError:
        return None


def _swap_active(sp: str) -> bool:
    r = subprocess.run(["swapon", "--show"], capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout:
        return False
    for line in r.stdout.splitlines()[1:]:
        parts = line.split()
        if parts and parts[0] == sp:
            return True
    return False


def _fstab_has_swap(sp: str) -> bool:
    r = subprocess.run(["sudo", "cat", "/etc/fstab"], capture_output=True, text=True)
    if r.returncode != 0:
        return False
    for line in r.stdout.splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        fields = s.split()
        if len(fields) >= 2 and fields[0] == sp and fields[1] == "none" and "swap" in fields:
            return True
    return False


def _ensure_swap(c: dict) -> None:
    if not _as_bool(c.get("SWAP_ENABLE", "0")):
        return
    raw_mb = str(c.get("SWAP_SIZE_MB", "2048")).strip()
    try:
        size_mb = int(raw_mb)
    except ValueError:
        print("CHYBA: SWAP_SIZE_MB musi byt cele cislo", file=sys.stderr)
        raise SystemExit(1) from None
    if size_mb < 64:
        print("CHYBA: SWAP_SIZE_MB prilis male (minimum 64)", file=sys.stderr)
        raise SystemExit(1) from None
    p0 = Path(c.get("SWAP_PATH", "/swapfile")).expanduser()
    if not p0.is_absolute():
        print("CHYBA: SWAP_PATH musi byt absolutni cesta", file=sys.stderr)
        raise SystemExit(1) from None
    sp = str(p0.resolve())

    want = size_mb * 1024 * 1024
    _banner("[1] swap: soubor, swapon, zapis do /etc/fstab (dle conf)")
    print(f"  swap: SWAP_ENABLE=1  path={sp}  size_MiB={size_mb}")

    if _swap_active(sp):
        print(f"         swap uz aktivni ({sp}) - preskoceno")
        return

    if _swapfile_exists(sp):
        got = _swapfile_size_bytes(sp)
        if got is not None and abs(got - want) > 4 * 1024 * 1024:
            print(
                f"         VAROVANI: {sp} existuje, velikost se lisi od conf ({got} B vs {want} B). "
                "Preskoceno - smazte soubor rucne nebo upravte SWAP_SIZE_MB.",
                file=sys.stderr,
            )
            return

    if not _swapfile_exists(sp):
        try:
            _sudo(["fallocate", "-l", f"{size_mb}M", sp], check=True)
        except subprocess.CalledProcessError:
            _sudo(
                ["dd", "if=/dev/zero", f"of={sp}", "bs=1M", f"count={str(size_mb)}", "status=none"],
                check=True,
            )

    _sudo(["chown", "root:root", sp], check=True)
    _sudo(["chmod", "600", sp], check=True)
    _sudo(["mkswap", "-f", sp], check=True)
    _sudo(["swapon", sp], check=True)

    if not _fstab_has_swap(sp):
        line = f"{sp} none swap sw 0 0\n"
        subprocess.run(["sudo", "tee", "-a", "/etc/fstab"], input=line, text=True, check=True)
        print("         /etc/fstab: pridan radek swap")
    else:
        print("         /etc/fstab: radek swap uz existuje")

    print("         swap: hotovo (overeni: swapon --show)")


def main() -> int:
    repo_dir = Path(__file__).resolve().parent
    conf_path = Path(os.environ.get("RMODUS_INSTALL_CONF", repo_dir / "rmodus_install.conf"))
    c = load_install_conf(conf_path)

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
    print(f"  Konfig: {conf_path}  ({'soubor' if conf_path.is_file() else 'vychozi DEFAULTS'})")
    print(f"  swap:   ENABLE={c['SWAP_ENABLE']}  SIZE_MB={c['SWAP_SIZE_MB']}  PATH={c['SWAP_PATH']}")
    print(f"  sw-nav: FETCH={c['FETCH_SW_NAV_MODULE']}  slozky: {c['SW_NAV_SPARSE_DIRS']}")
    print(
        f"  Xsens:  FETCH={c['FETCH_XSENS_DRIVER']}  xspublic={c['BUILD_XSPUBLIC']}  udev={c['INSTALL_XSENS_UDEV']}"
    )
    print(
        f"  rf2o:   FETCH={c['FETCH_RF2O']}  samostatna faze buildu={c['BUILD_RF2O_SEPARATE_PHASE']}"
    )
    print(f"  rosdep: vlastni R-MODUS pravidla={c['INSTALL_RMODUS_ROSDEP_RULES']}")
    print(f"  pip rmodus_*: {c['INSTALL_RMODUS_HW_PIP']}")
    print("")

    _ensure_swap(c)

    # [2]
    _banner("[2] Apt: aktualizace + curl, git, build-essential, pip (+ libbz2/bzip2 v jedne transakci)")
    _apt(["update"], check=True)
    _apt(["-y", "upgrade"], check=True)
    _apt_install_base_toolchain()

    # [3]
    print("")
    _banner(f"[3] ROS 2 {ros_distro}: repozitar packages.ros.org, ros-base, ros-dev-tools")
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
    _banner(f"[4] Workspace {ws_path} - klonovani repozitaru")
    ws_path.mkdir(parents=True, exist_ok=True)
    (ws_path / "src").mkdir(parents=True, exist_ok=True)

    if _as_bool(c["FETCH_SW_NAV_MODULE"]):
        print(f"  (4a) R-MODUS/sw-nav-module (vetev {c['SW_NAV_BRANCH']}) -> {c['SW_NAV_SPARSE_DIRS']}")
        _sparse_clone_flat_multi(
            "https://github.com/R-MODUS/sw-nav-module.git",
            c["SW_NAV_BRANCH"],
            snav_dir,
            sw_nav_dirs,
        )
        _sparse_clone_fix_missing(snav_dir, sw_nav_dirs)
    else:
        print("  (4a) sw-nav-module - preskoceno (FETCH_SW_NAV_MODULE=0)")

    if _as_bool(c["FETCH_XSENS_DRIVER"]):
        print("  (4b) Xsens MTi ROS2 driver (vetev ros2)")
        _sparse_clone_nested_folder(
            "https://github.com/xsenssupport/Xsens_MTi_ROS_Driver_and_Ntrip_Client.git",
            "ros2",
            xsens_ws_dir,
            "src/xsens_mti_ros2_driver/",
        )
    else:
        print("  (4b) Xsens driver - preskoceno (FETCH_XSENS_DRIVER=0)")

    if _as_bool(c["FETCH_RF2O"]):
        print("  (4c) rf2o_laser_odometry (vetev ros2)")
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
        print("  (4c) rf2o - preskoceno (FETCH_RF2O=0)")

    # [5]
    print("")
    _banner("[5] Xsens xspublic - make v lib/xspublic")
    xspublic_dir = xsens_ws_dir / "src" / "xsens_mti_ros2_driver" / "lib" / "xspublic"
    if _as_bool(c["FETCH_XSENS_DRIVER"]) and _as_bool(c["BUILD_XSPUBLIC"]):
        if xspublic_dir.is_dir():
            _run(["make"], cwd=xspublic_dir, check=True)
        else:
            print("         (xspublic nenalezen - preskoceno)")
    else:
        print(
            f"         (preskoceno: FETCH_XSENS_DRIVER={c['FETCH_XSENS_DRIVER']}, BUILD_XSPUBLIC={c['BUILD_XSPUBLIC']})"
        )

    if not _find_package_xml_under(ws_path / "src"):
        print(
            f"CHYBA: v {ws_path / 'src'} neni zadny package.xml - zapnete alespon jeden zdroj v conf.",
            file=sys.stderr,
        )
        return 1

    # [6a]
    print("")
    _banner("[6a] rosdep - zavislosti z package.xml ve src/")
    if _as_bool(c["INSTALL_RMODUS_ROSDEP_RULES"]):
        print("  (6a0) R-MODUS/sw-nav-module - rosdep/rmodus_custom.yaml -> /etc/ros/rosdep/")
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
                f"         VAROVANI: nelze stahnout {yaml_url} - pokracuji bez vlastnich rosdep klicu R-MODUS",
                file=sys.stderr,
            )
            _sudo(["rm", "-f", str(tmp)], check=False)
    else:
        print("  (6a0) vlastni rosdep pravidla R-MODUS - preskoceno (INSTALL_RMODUS_ROSDEP_RULES=0)")

    print("  (6a1) rosdep install - systemove (a pip) zavislosti z package.xml")
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

    if _as_bool(c["INSTALL_RMODUS_HW_PIP"]):
        print("  (6a2) pip install - rmodus_* s requirements-pip.txt (PEP 668: --user --break-system-packages)")
        pip_base = [
            sys.executable,
            "-m",
            "pip",
            "install",
            "--user",
            "--upgrade",
            "--break-system-packages",
        ]
        pip_reqs = _rmodus_pip_requirement_files(ws_path / "src")
        if not pip_reqs:
            print(
                "         VAROVANI: pod src/ zadny rmodus_*/requirements-pip.txt - pip krok nic neinstaluje.",
                file=sys.stderr,
            )
        for req in pip_reqs:
            try:
                rel = req.relative_to(ws_path)
            except ValueError:
                rel = req
            print(f"         pip -r {rel}")
            _run([*pip_base, "-r", str(req)], check=True)
    elif not _as_bool(c["INSTALL_RMODUS_HW_PIP"]):
        print("  (6a2) pip rmodus_* - preskoceno (INSTALL_RMODUS_HW_PIP=0)")

    # [6b]/[6c]
    build_env = os.environ.copy()
    build_env.setdefault("CMAKE_BUILD_PARALLEL_LEVEL", "1")
    build_env.setdefault("MAKEFLAGS", "-j1")

    if _as_bool(c["FETCH_RF2O"]) and _as_bool(c["BUILD_RF2O_SEPARATE_PHASE"]):
        print("")
        _banner("[6b] colcon build - balicky ve workspace krome rf2o_laser_odometry")
        _bash_script(
            f"source /opt/ros/{ros_distro}/setup.bash && "
            "colcon build --symlink-install --parallel-workers 1 --packages-skip rf2o_laser_odometry",
            cwd=ws_path,
            env=build_env,
        )
        print("")
        _banner("[6c] colcon build - pouze rf2o_laser_odometry (linker, setreni RAM)")
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
        _banner("[6b] colcon build - cely workspace (jedna faze)")
        _bash_script(
            f"source /opt/ros/{ros_distro}/setup.bash && colcon build --symlink-install --parallel-workers 1",
            cwd=ws_path,
            env=build_env,
        )

    if not (ws_path / "install" / "setup.bash").is_file():
        print(f"CHYBA: chybi {ws_path / 'install' / 'setup.bash'} - build nedobehl.", file=sys.stderr)
        return 1

    # [7]
    print("")
    _banner("[7] ~/.bashrc - source /opt/ros a install/setup.bash")
    bashrc = home / ".bashrc"
    marker = f"/opt/ros/{ros_distro}/setup.bash"
    ros_env = deploy_path / "rmodus_ros.env"
    if bashrc.is_file() and Path(f"/opt/ros/{ros_distro}/setup.bash").is_file():
        text = bashrc.read_text(encoding="utf-8", errors="replace")
        if marker not in text:
            block = (
                "\n# --- RMODUS (pridano install.py) ---\n"
                f'test -f "{ros_env}" && {{ set -a; source "{ros_env}"; set +a; }}\n'
                f"source /opt/ros/{ros_distro}/setup.bash\n"
                f'test -f "{ws_path}/install/setup.bash" && source "{ws_path}/install/setup.bash"\n'
            )
            with bashrc.open("a", encoding="utf-8") as f:
                f.write(block)
            print("         radky pridany do ~/.bashrc")
        else:
            print("         ~/.bashrc uz obsahuje source pro ROS - beze zmeny")

    # [8]
    print("")
    _banner("[8] Prava k /dev/ttyUSB*, /dev/ttyACM* - skupiny dialout (a plugdev)")
    _sudo(["usermod", "-aG", "dialout", user], check=True)
    plugdev = subprocess.run(["getent", "group", "plugdev"], capture_output=True).returncode == 0
    if plugdev:
        _sudo(["usermod", "-aG", "plugdev", user], check=True)
        print(f"         uzivatel {user} pridan do: dialout, plugdev")
    else:
        print(f"         uzivatel {user} pridan do: dialout (skupina plugdev na systemu neni)")
    print("         -> Skupiny plati po novem prihlaseni nebo: newgrp dialout")
    print("         -> LiDAR musi byt pripojeny; port nemusi byt ttyUSB0 (viz ls nize).")

    # [9a]
    print("")
    _banner("[9a] udev - pravidla pro Xsens MTi (99-xsens-mti.rules)")
    udev_src = xsens_ws_dir / "src" / "xsens_mti_ros2_driver" / "resources"
    if _as_bool(c["INSTALL_XSENS_UDEV"]) and udev_src.is_dir():
        rules = udev_src / "99-xsens-mti.rules"
        if rules.is_file():
            _sudo(["cp", str(rules), "/etc/udev/rules.d/"], check=True)
            _sudo(["udevadm", "control", "--reload-rules"], check=True)
            _sudo(["udevadm", "trigger"], check=True)
            print("         Pravidla zkopirovana a udev znovu nacten.")
        else:
            print("         Soubor 99-xsens-mti.rules nenalezen - preskoceno.")
    elif not _as_bool(c["INSTALL_XSENS_UDEV"]):
        print("         Preskoceno (INSTALL_XSENS_UDEV=0).")
    else:
        print("         Adresar resources/ nenalezen - preskoceno (chybi Xsens driver ve src?).")

    # [9b]
    print("")
    _banner("[9b] systemd - jednotka rmodus.service (enable)")
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
        print("         Sluzba rmodus povolena (enable). Start: sudo systemctl start rmodus")
    elif not _as_bool(c["ENABLE_SYSTEMD_RMODUS"]):
        print("         Preskoceno (ENABLE_SYSTEMD_RMODUS=0).")
    else:
        print(f"         Chybi {svc_src} nebo {ep_tpl} v {deploy_path}.")

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
        print(f"CHYBA: prikaz selhal (exit {e.returncode}): {e.cmd}", file=sys.stderr)
        raise SystemExit(e.returncode)
