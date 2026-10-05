# Instalace

Dvě cesty. Předvolba stáhne setup a hned instaluje podle jména. Vlastní nejdřív stáhne soubory, pak se upraví `install.yaml`.

## Předvolba

`web`, `sim`, `robot` nebo `full` — soubory `presets/*.yaml`.

```bash
curl -sSL https://raw.githubusercontent.com/R-MODUS/sw-install/main/bootstrap.sh | bash -s -- robot
```

| jméno | co stáhne |
|---|---|
| `web` | jen web: UI, profily, model |
| `sim` | Gazebo, podvozek, navigace, web; bez HW krabičky |
| `robot` | reálný robot: HW, podvozek, navigace, web, micro-ROS; bez Gazebo |
| `full` | robot + Gazebo + rf2o |

Po klonu totéž bez curl:

```bash
cd ~/rmodus/setup
python3 -u install.py sim
```

## Vlastní konfigurace

### 1. Stáhnout setup

```bash
sudo apt update && sudo apt install -y ca-certificates git python3
git clone https://github.com/R-MODUS/sw-install.git ~/rmodus/setup
```

### 2. Upravit konfiguraci

```bash
nano ~/rmodus/setup/install.yaml
```

Klíč, který v yaml chybí, vezme `install.py` ze svých `DEFAULTS`.

### 3. Instalovat

```bash
cd ~/rmodus/setup
python3 -u install.py
```

### Strom na Linuxu (po instalaci)

```
~/rmodus/
  setup/          sw-install (`install.py`, `install.yaml`, `presets/`, `examples/`, `network/`, `systemd/`)
  ros2_ws/        colcon workspace (src/, install/)
  configs/
    profiles/     robot profiles `*.yaml` (template: `setup/examples/rmodus-example.yaml`)
    active        active profile name (after install: `rmodus-example`)
    network.yaml  Wi-Fi (template: `setup/examples/rmodus-network.example.yaml`, chmod 600)
  data/           copy of **`manual.pdf`** from sw-install root (`setup/manual.pdf`), step **[0b]**
```

- **`manual.pdf`** lives in **`sw-install`** next to `install.py` (no `defaults/` folder).
- **Robot profile:** `profiles/<name>.yaml` + **`active`** pointer. Install **always overwrites** `profiles/rmodus-example.yaml` from `setup/examples/`. Other profiles, `active`, and `network.yaml` are **kept** on reinstall.
- **`rmodus.yaml` (bringup package)** = ROS default; `bringup:` (+ `extras`) + `/**` must match the example profile.
- **Network:** separate **`network.yaml`** (`boot.network` + `network:`). Systemd **`rmodus-network`** is enable-only (no start). Netplan `99-rmodus-nm.yaml`; apply after reboot.
- **Web:** nginx reverse proxy **`:80` → `:8080`** (`ENABLE_RMODUS_WEB_PROXY`). URL without port: `http://<ip>/`.
- **mDNS:** Avahi (`ENABLE_RMODUS_MDNS`) + default **`RMODUS_HOSTNAME=rmodus`** → `http://rmodus.local/`. Install overwrites hostname (Imager value does not matter). SSH user account unchanged. Empty `RMODUS_HOSTNAME=` = leave hostname as-is.
- **`boot.rmodus`** in robot profile; **`boot.network`** in network.yaml. `false` = no-op at start.
- **`rmodus.service`** → entrypoint reads `active` and launches `robot_yaml:=profiles/<active>.yaml`.
- Profile CRUD: ROS package **`rmodus_config`** (`bringup.config`, services `/rmodus/config/*`; web UI / `ros2`).
- Web UI: **`web:`** block in the active robot profile.

`install.py` krok **[0]** tyto složky vytvoří na začátku.

### Log / výstup z `install.py` v konzoli

- **Zároveň do souboru** (a pořád na konzoli):  
  `cd ~/rmodus/setup && PYTHONUNBUFFERED=1 python3 -u install.py 2>&1 | tee ~/rmodus-install.log`

**Důležité:** na větvi **`main`** musí být **`install.py`** i **`install.yaml`**. `git reset --hard` přepíše i upravený `install.yaml` — předtím si ho schovejte.

Instalaci spusťte pod uživatelem **admin** (systemd doplní `User=` při instalaci).

### Konfigurace

Předvolba je `presets/<jméno>.yaml`. Vlastní úpravy jsou v `~/rmodus/setup/install.yaml`. `install.py` má jen `DEFAULTS` pro chybějící klíč.
`RMODUS_ROOT`, `DEPLOY_PATH`, `WS_PATH`, `SWAP_*`, `SW_NAV_SPARSE_DIRS`,
`FETCH_RF2O` (default 0), `FETCH_TWIST_MUX` (default 1, apt),
`SIM` (default 0; `1` = apt `ros-<distro>-ros-gz` + `rmodus_gazebo` ze sw-nav-module), `INSTALL_RMODUS_HW_PIP`, rosdep, `ENABLE_RMODUS_NETWORK`,
`ENABLE_RMODUS_WEB_PROXY`, `ENABLE_RMODUS_MDNS`, `RMODUS_HOSTNAME`.
Lidar/IMU drivery (Neato, Xsens, …) install nestahuje.

### Po instalaci

```bash
source ~/.bashrc          # ROS + ros2_ws overlay v SSH shellu
ros2 doctor
sudo systemctl start rmodus
journalctl -u rmodus -f
```

Zkratky v `~/.bashrc` (blok RMODUS):

```bash
rmodus start|stop|restart|status|enable|disable|log   # rmodus.service
rmodus net stop|start|status|log                      # rmodus-network.service
```

Entrypoint pro systemd: **`~/rmodus/setup/systemd/rmodus_entrypoint.sh`** (ne kopie v `~/`).

Ruční přeinstalace. `git reset --hard` přepíše i upravený `install.yaml` (předvolby v `presets/` jsou v gitu, ty se obnoví):

```bash
cd ~/rmodus/setup
cp -a install.yaml /tmp/rmodus-install.yaml.bak
git fetch origin && git reset --hard origin/main
cp -a /tmp/rmodus-install.yaml.bak install.yaml
python3 -u install.py
```

Předvolba po aktualizaci: `python3 -u install.py robot` (nebo `web` / `sim` / `full`).
