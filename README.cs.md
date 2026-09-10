# one-liner

```bash
sudo apt update && sudo apt install -y curl && curl -sSL https://raw.githubusercontent.com/R-MODUS/sw-install/main/bootstrap.sh | bash
```

(Pri potizich s vystupem zkuste `curl -SL` bez `-s`, at vidite pripadne chyby ze stazeni.)

### Strom na Linuxu (po bootstrap / install)

```
~/rmodus/
  setup/          sw-install (`install.py`, `examples/`, `network/`, `systemd/`)
  ros2_ws/        colcon workspace (src/, install/)
  configs/
    profiles/     robot profily `*.yaml` (vzor: `setup/examples/rmodus-example.yaml`)
    active        jméno aktivního profilu (po install: `rmodus-example`)
    network.yaml  Wi-Fi (vzor: `setup/examples/rmodus-network.example.yaml`, chmod 600)
  data/           kopie **`manual.pdf`** z korene sw-install (`setup/manual.pdf`), krok **[0b]**
```

- **`manual.pdf`** lezi primo v **`sw-install`** vedle `install.py` (neni slozka `defaults/`).
- **Robot profil:** `profiles/<name>.yaml` + ukazatel **`active`**. Install **vždy přepíše** `profiles/rmodus-example.yaml` ze `setup/examples/`. Ostatní profily, `active` a `network.yaml` při reinstall **zachová**.
- **`rmodus.yaml` (bringup package)** = ROS default; `bringup:` + `/**` musi sedet s example profilem.
- **Sit:** samostatny **`network.yaml`** (`boot.network` + `network:`). Systemd **`rmodus-network`** jen enable (ne start). Netplan `99-rmodus-nm.yaml`; apply po rebootu.
- **`boot.rmodus`** v robot profilu; **`boot.network`** v network.yaml. `false` = no-op pri startu.
- **`rmodus.service`** → entrypoint cte `active` a spusti `robot_yaml:=profiles/<active>.yaml`.
- Sprava profilu: ROS balicek **`rmodus_config`** (`bringup.config`, services `/rmodus/config/*`; web UI / `ros2`).
- Web UI: blok **`web:`** v aktivnim robot profilu.

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
Lidar/IMU drivery (Neato, Xsens, …) install netaha — resit mimo / podle potreby.

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
