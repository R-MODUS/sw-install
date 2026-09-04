# one-liner

```bash
sudo apt update && sudo apt install -y curl && curl -sSL https://raw.githubusercontent.com/R-MODUS/sw-install/main/bootstrap.sh | bash
```

(Pri potizich s vystupem zkuste `curl -SL` bez `-s`, at vidite pripadne chyby ze stazeni.)

### Strom na Linuxu (po bootstrap / install)

```
~/rmodus/
  setup/          sw-install (install.py, bootstrap, rmodus_entrypoint.sh, rmodus_ros.env, network/)
  ros2_ws/        colcon workspace (src/, install/)
  configs/        `robot.yaml` (z sw-nav-module) a `network.yaml` (z sw-install/network; existujici se neprepisuji)
  data/           kopie **`manual.pdf`** z korene sw-install (`setup/manual.pdf`), krok **[0b]**
```

- **`manual.pdf`** lezi primo v **`sw-install`** vedle `install.py` (neni slozka `defaults/`).
- **`robot.yaml`** do `~/rmodus/configs/` instalator zkopiuje ze **`ros2_ws/src/sw_nav_module/rmodus_hw/config/robot.yaml`** (jediny zdroj pravdy je **sw-nav-module**). Pokud cil **`~/rmodus/configs/robot.yaml`** uz existuje, kopie se preskoci. Bez `FETCH_SW_NAV_MODULE` krok **[4d]** vypise VAROVANI.
- **`network.yaml`** do `~/rmodus/configs/` instalator zkopiuje ze **`setup/network/network.yaml.example`** (krok **[4e]**). Existujici soubor se neprepisuje. `mode: client|ap|ethernet`. Systemd jednotka **`rmodus-network`** se pri instalaci jen **enable** (ne start), aby SSH pres WiFi nespadlo. Zaroven se zapise `/etc/netplan/99-rmodus-nm.yaml` (`renderer: NetworkManager`); `netplan apply` az po rebootu. Prvni SSH: Wi-Fi v Raspberry Pi Imageru; po rebootu plati `network.yaml`. Debug AP raději pres Ethernet.

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

Entrypoint pro systemd: **`~/rmodus/setup/rmodus_entrypoint.sh`** (ne kopie v `~/`).

Rucni preinstalace:

```bash
cd ~/rmodus/setup
git fetch origin && git reset --hard origin/main
python3 -u install.py
```
