# one-liner

```bash
sudo apt update && sudo apt install -y curl && curl -sSL https://raw.githubusercontent.com/R-MODUS/sw-install/main/bootstrap.sh | bash
```

Instalaci spusťte pod uživatelem **admin** (služba `rmodus.service` je pro `/home/admin`).

```bash
sudo systemctl stop rmodus
sudo systemctl restart rmodus
journalctl -u rmodus -f
```

sudo swapoff -a
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile