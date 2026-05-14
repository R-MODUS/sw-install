# one-liner

```bash
sudo apt update && sudo apt install -y curl && curl -sSL https://raw.githubusercontent.com/R-MODUS/sw-install/main/bootstrap.sh | bash
```

(Při potížích s výstupem zkuste `curl -SL` bez `-s`, ať vidíte případné chyby ze stažení.)

### Log / výstup z `install.py` v konzoli

- Bootstrap už spouští **`python3 -u`** a exportuje **`PYTHONUNBUFFERED=1`** — výstup by měl jít na obrazovku hned.
- **Zároveň do souboru** (a pořád na konzoli):  
  `curl -sSL …/bootstrap.sh | tee /tmp/rmodus-bootstrap.log | bash`
- **Jen instalátor** po klonu:  
  `cd ~/rmodus_setup && PYTHONUNBUFFERED=1 python3 -u install.py 2>&1 | tee ~/rmodus-install.log`
- **Víc šumu z shellu** (kdo spouští co):  
  `bash -x ~/rmodus_setup/bootstrap.sh` (nejdřív `curl -o ~/bootstrap.sh …`, pak `bash -x ~/bootstrap.sh`).

**Důležité:** na větvi **`main`** na GitHubu musí být soubor **`install.py`**. Pokud po `ls ~/rmodus_setup` `install.py` nevidíte, změny nejsou pushnuté — po pushnutí na Pi: `cd ~/rmodus_setup && git fetch origin && git reset --hard origin/main` a znovu spusťte bootstrap / `python3 -u install.py`.

**Bootstrap** doinstaluje `python3` a `git` (chybí-li), stáhne repozitář a spustí **`python3 -u install.py`** (nebufferovaný výpis). Nastaví také `NEEDRESTART_MODE=a`, aby apt po upgradu méně kazil výstup v SSH.

Instalaci spusťte pod uživatelem **admin** (šablona `rmodus.service` používá `User=__SERVICE_USER__` — při instalaci se doplní aktuální uživatel).

Hlavní logika je v **`install.py`**. **`rmodus_install.sh`** jen volá `python3 install.py` kvůli starým návodům.

Sdílené proměnné ROS 2: **`rmodus_ros.env`** v adresáři deploy (`DEPLOY_PATH`, výchozí `~/rmodus_setup`). Doplní se do `~/.bashrc` a do vygenerovaného `~/rmodus_entrypoint.sh`.

### Volitelná konfigurace (`rmodus_install.conf`)

V adresáři `rmodus_setup` upravte `rmodus_install.conf` (nebo `export RMODUS_INSTALL_CONF=…` před spuštěním). Volitelné klíče: `INSTALL_RMODUS_ROSDEP_RULES`, `RMODUS_ROSDEP_YAML_URL`, `INSTALL_RMODUS_HW_PIP` (pip z `rmodus_hw/requirements-pip.txt` po rosdep).

```bash
sudo systemctl stop rmodus
sudo systemctl restart rmodus
journalctl -u rmodus -f
```

Ruční přeinstalace z klonu:

```bash
cd ~/rmodus_setup
git fetch origin && git reset --hard origin/main
python3 install.py
```
