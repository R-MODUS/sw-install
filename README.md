# one-liner

```bash
sudo apt update && sudo apt install -y curl && curl -sSL https://raw.githubusercontent.com/R-MODUS/sw-install/main/bootstrap.sh | bash
```

(Pri potizich s vystupem zkuste `curl -SL` bez `-s`, at vidite pripadne chyby ze stazeni.)

### Strom na Linuxu (po bootstrap / install)

```
~/rmodus/
  setup/          sw-install (`install.py`, `examples/`, `network/`, `systemd/`, `config/`)
  ros2_ws/        colcon workspace (src/, install/)
  configs/
    profiles/     robot profiles `*.yaml` (template: `setup/examples/rmodus-example.yaml`)
    active        active profile name (after install: `rmodus-example`)
    network.yaml  Wi-Fi (template: `setup/examples/rmodus-network.example.yaml`, chmod 600)
  data/           copy of **`manual.pdf`** from sw-install root (`setup/manual.pdf`), step **[0b]**
```

- **`manual.pdf`** lives in **`sw-install`** next to `install.py` (no `defaults/` folder).
- **Robot profile:** `profiles/<name>.yaml` + **`active`** pointer. Install copies the example only if missing — **reinstall never overwrites any profile, active, or network.yaml**.
- **`rmodus.yaml` (bringup package)** = ROS default; `bringup:` + `/**` must match the example profile.
- **Network:** separate **`network.yaml`** (`boot.network` + `network:`). Systemd **`rmodus-network`** is enable-only (no start). Netplan `99-rmodus-nm.yaml`; apply after reboot.
- **`boot.rmodus`** in robot profile; **`boot.network`** in network.yaml. `false` = no-op at start.
- **`rmodus.service`** → active profile via `ros2 launch rmodus_bringup … robot_yaml:=profiles/<active>.yaml`.
- CLI: **`rmodus-config list|activate|path`**; ROS package **`rmodus_config`**.
- Web UI: **`web:`** block in the active robot profile.

Bootstrap i `install.py` krok **[0]** tyto slozky vytvori na zacatku.

### Log / vystup z `install.py` v konzoli

- Bootstrap uz spousti **`python3 -u`** a exportuje **`PYTHONUNBUFFERED=1`** - vystup by mel jit na obrazovku hned.
- **Zaroven do souboru** (a porad na konzoli):  
  `curl -sSL .../bootstrap.sh | tee /tmp/rmodus-bootstrap.log | bash`
- **Jen instalator** po klonu:  
  `cd ~/rmodus/setup && PYTHONUNBUFFERED=1 python3 -u install.py 2>&1 | tee ~/rmodus-install.log`

**Dulezite:** na vetvi **`main`** musi byt **`install.py`** v repu. Po pushnuti na Pi:  
`cd ~/rmodus/setup && git fetch origin && git reset --hard origin/main`

**Bootstrap** klonuje repozitar do **`~/rmodus/setup`**, doinstaluje `python3` / `git` a spusti **`python3 -u install.py`**.

Instalaci spustte pod uzivatelem **admin** (systemd doplni `User=` pri instalaci).

### Konfigurace (`rmodus_install.conf` v `~/rmodus/setup`)

Volitelne: `RMODUS_ROOT`, `DEPLOY_PATH`, `WS_PATH`, `SWAP_*`, `SW_NAV_SPARSE_DIRS`,
`FETCH_RF2O` (default 0), `INSTALL_RMODUS_HW_PIP`, rosdep, `ENABLE_RMODUS_NETWORK`, atd.
Lidar/IMU drivers (Neato, Xsens, …) are not fetched by install — handle outside / as needed.

### Po instalaci

```bash
source ~/.bashrc          # ROS + ros2_ws overlay v SSH shellu
ros2 doctor
sudo systemctl start rmodus
journalctl -u rmodus -f
```

Entrypoint pro systemd: **`~/rmodus/setup/systemd/rmodus_entrypoint.sh`** (ne kopie v `~/`).

Rucni preinstalace:

```bash
cd ~/rmodus/setup
git fetch origin && git reset --hard origin/main
python3 -u install.py
```
