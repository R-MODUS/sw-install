# one-liner

```bash
sudo apt update && sudo apt install -y curl && curl -sSL https://raw.githubusercontent.com/R-MODUS/sw-install/main/bootstrap.sh | bash
```

(Pri potizich s vystupem zkuste `curl -SL` bez `-s`, at vidite pripadne chyby ze stazeni.)

### Log / vystup z `install.py` v konzoli

- Bootstrap uz spousti **`python3 -u`** a exportuje **`PYTHONUNBUFFERED=1`** - vystup by mel jit na obrazovku hned.
- **Zaroven do souboru** (a porad na konzoli):  
  `curl -sSL .../bootstrap.sh | tee /tmp/rmodus-bootstrap.log | bash`
- **Jen instalator** po klonu:  
  `cd ~/rmodus_setup && PYTHONUNBUFFERED=1 python3 -u install.py 2>&1 | tee ~/rmodus-install.log`
- **Vic sumu ze shellu** (kdo spousti co):  
  `bash -x ~/rmodus_setup/bootstrap.sh` (nejdriv `curl -o ~/bootstrap.sh ...`, pak `bash -x ~/bootstrap.sh`).

**Dulezite:** na vetvi **`main`** na GitHubu musi byt soubor **`install.py`**. Pokud po `ls ~/rmodus_setup` `install.py` nevidite, zmeny nejsou pushnute - po pushnuti na Pi: `cd ~/rmodus_setup && git fetch origin && git reset --hard origin/main` a znovu spustte bootstrap / `python3 -u install.py`.

**Bootstrap** doinstaluje `python3` a `git` (chybi-li), stahne repozitar a spusti **`python3 -u install.py`** (nebufferovany vystup). Nastavi take `NEEDRESTART_MODE=a`, aby apt po upgradu mene kazil vystup v SSH.

Instalaci spustte pod uzivatelem **admin** (sablona `rmodus.service` pouziva `User=__SERVICE_USER__` - pri instalaci se doplni aktualni uzivatel).

Hlavni logika je v **`install.py`**. **`rmodus_install.sh`** jen vola `python3 install.py` kvuli starym navodum.

Sdilene promenne ROS 2: **`rmodus_ros.env`** v adresari deploy (`DEPLOY_PATH`, vychozi `~/rmodus_setup`). Doplni se do `~/.bashrc` a do vygenerovaneho `~/rmodus_entrypoint.sh`.

### Volitelna konfigurace (`rmodus_install.conf`)

V adresari `rmodus_setup` upravte `rmodus_install.conf` (nebo `export RMODUS_INSTALL_CONF=...` pred spustenim). Sablona vsech klicu: **`rmodus_install.conf.example`**.

Klice mimo jine: `SWAP_ENABLE`, `SWAP_SIZE_MB`, `SWAP_PATH` (swap soubor pred apt/colcon), `INSTALL_RMODUS_ROSDEP_RULES`, `RMODUS_ROSDEP_YAML_URL`, `INSTALL_RMODUS_HW_PIP` (pip z kazdeho `rmodus_*/requirements-pip.txt` pod `src/` po rosdep; nazev klice je historicky).

```bash
sudo systemctl stop rmodus
sudo systemctl restart rmodus
journalctl -u rmodus -f
```

Rucni preinstalace z klonu:

```bash
cd ~/rmodus_setup
git fetch origin && git reset --hard origin/main
python3 install.py
```
