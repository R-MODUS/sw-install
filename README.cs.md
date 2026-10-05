# Instalace

Tři kroky: stáhnout setup, upravit `install.yaml`, spustit instalaci.

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
  setup/          sw-install (`install.py`, `install.yaml`, `examples/`, `network/`, `systemd/`)
  ros2_ws/        colcon workspace (src/, install/)
  configs/
    profiles/     robot profily `*.yaml` (vzor: `setup/examples/rmodus-example.yaml`)
    active        jméno aktivního profilu (po install: `rmodus-example`)
    network.yaml  Wi-Fi (vzor: `setup/examples/rmodus-network.example.yaml`, chmod 600)
  data/           kopie **`manual.pdf`** z korene sw-install (`setup/manual.pdf`), krok **[0b]**
```

- **`manual.pdf`** lezi primo v **`sw-install`** vedle `install.py` (neni slozka `defaults/`).
- **Robot profil:** `profiles/<name>.yaml` + ukazatel **`active`**. Install **vždy přepíše** `profiles/rmodus-example.yaml` ze `setup/examples/`. Ostatní profily, `active` a `network.yaml` při reinstall **zachová**.
- **`rmodus.yaml` (bringup package)** = ROS default; `bringup:` (+ `extras`) + `/**` musi sedet s example profilem.
- **Sit:** samostatny **`network.yaml`** (`boot.network` + `network:`). Systemd **`rmodus-network`** jen enable (ne start). Netplan `99-rmodus-nm.yaml`; apply po rebootu.
- **Web:** nginx reverse proxy **`:80` → `:8080`** (`ENABLE_RMODUS_WEB_PROXY`). URL bez portu: `http://<ip>/`.
- **mDNS:** Avahi (`ENABLE_RMODUS_MDNS`) + default **`RMODUS_HOSTNAME=rmodus`** → `http://rmodus.local/`. Install hostname přepíše (Imager hodnota nevadí). SSH účet se nemění. Prázdné `RMODUS_HOSTNAME=` = nemenit.
- **`boot.rmodus`** v robot profilu; **`boot.network`** v network.yaml. `false` = no-op pri startu.
- **`rmodus.service`** → entrypoint cte `active` a spusti `robot_yaml:=profiles/<active>.yaml`.
- Sprava profilu: ROS balicek **`rmodus_config`** (`bringup.config`, services `/rmodus/config/*`; web UI / `ros2`).
- Web UI: blok **`web:`** v aktivnim robot profilu.

`install.py` krok **[0]** tyto složky vytvoří na začátku.

### Log / výstup z `install.py` v konzoli

- **Zároveň do souboru** (a pořád na konzoli):  
  `cd ~/rmodus/setup && PYTHONUNBUFFERED=1 python3 -u install.py 2>&1 | tee ~/rmodus-install.log`

**Důležité:** na větvi **`main`** musí být **`install.py`** i **`install.yaml`**. `git reset --hard` přepíše i upravený `install.yaml` — předtím si ho schovejte.

Instalaci spusťte pod uživatelem **admin** (systemd doplní `User=` při instalaci).

### Konfigurace (`install.yaml` vedle `install.py`)

Upravuje se **`~/rmodus/setup/install.yaml`**, ne `install.py`. V Pythonu jsou jen `DEFAULTS` pro chybějící klíč.
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

Ruční přeinstalace (záloha `install.yaml`, `reset --hard` ho přepíše):

```bash
cd ~/rmodus/setup
cp -a install.yaml /tmp/rmodus-install.yaml.bak
git fetch origin && git reset --hard origin/main
cp -a /tmp/rmodus-install.yaml.bak install.yaml
python3 -u install.py
```
