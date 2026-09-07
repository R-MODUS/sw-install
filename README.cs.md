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
  configs/        profily `*.yaml`; aktivni kopie `current/current.yaml` (vzor: `setup/examples/rmodus-example.yaml`)
  data/           kopie **`manual.pdf`** z korene sw-install (`setup/manual.pdf`), krok **[0b]**
```

- **`manual.pdf`** lezi primo v **`sw-install`** vedle `install.py` (neni slozka `defaults/`).
- **`robot.yaml` se nekopiruje.** Vzor celeho profilu je **`setup/examples/rmodus-example.yaml`** (`meta`, `network`, `web`, hardware). Profily patri do **`~/rmodus/configs/*.yaml`**; po bootu plati kopie **`~/rmodus/configs/current/current.yaml`** (instalator ji nevytvari).
- Sit: blok **`network:`** v **`current.yaml`** (`mode: client|ap|ethernet`). Systemd jednotka **`rmodus-network`** se pri instalaci jen **enable** (ne start), aby SSH pres WiFi nespadlo. Zaroven se zapise `/etc/netplan/99-rmodus-nm.yaml` (`renderer: NetworkManager`); `netplan apply` az po rebootu. Prvni SSH: Wi-Fi v Raspberry Pi Imageru. Debug AP raději pres Ethernet.
- Web UI: blok **`web:`** v **`current.yaml`** (host, port, PIN, topicy, záložky). Čte ho `rmodus_web`; bez bloku platí vestavěné defaulty.

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

Volitelne: `RMODUS_ROOT`, `DEPLOY_PATH`, `WS_PATH`, `SWAP_*`, `INSTALL_RMODUS_HW_PIP`, rosdep klice, `ENABLE_RMODUS_NETWORK`, atd.

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
