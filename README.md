# Homelab Public Bootstrap

This guide helps you:
1) Enable SSH on Ubuntu, and  
2) Deploy your Docker homelab from a **private** GitHub repo via a one-command bootstrap (or manual steps).

> **Assumptions**
> - Ubuntu 22.04+ with sudo access  
> - Your **private** repo holds your Compose stacks   
> - You’ll run these commands **on the Ubuntu server** you’re setting up

---

## 1) Enabling SSH on Ubuntu
### Install ifconfig support
```bash
# Update package index
sudo apt update

# Install curl (downloads), net-tools (ifconfig), and OpenSSH server
sudo apt install -y curl net-tools openssh-server

# Enable and start SSH service
sudo systemctl enable --now ssh

# Allow SSH through UFW firewall if installed
if command -v ufw >/dev/null 2>&1; then
  sudo ufw allow OpenSSH
  sudo ufw enable
fi

# Show SSH service status and IP address
systemctl status ssh --no-pager
echo "Server IP addresses:"
hostname -I

```

### Recommended: use SSH keys (and harden)
On your **client** (laptop/PC):
```bash
ssh-keygen -t ed25519 -C "homelab"
ssh-copy-id -i ~/.ssh/id_ed25519.pub <your-username>@<server-ip>
```
After key login works, harden the server:
```bash
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
sudo nano /etc/ssh/sshd_config
# set:
#   PermitRootLogin no
#   PasswordAuthentication no
sudo systemctl restart ssh
```

---

## 2) Deploying everything (Git-driven homelab)

You have two paths: **A (one-command bootstrap)** or **B (manual)**.

### A) One-command bootstrap (automatic)

**What it does**
- Installs Docker + Compose (if missing)  
- Clones/updates your **private** homelab repo (Compose stacks)  
- Auto-creates any missing `.env` from `.env.example`  
- Pulls images and brings stacks up  
- (Optional) Sets a nightly auto-update cron  

**Prepare: add an SSH deploy key on the server (one-time)**
```bash
ssh-keygen -t ed25519 -C "homelab" -f ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub
# Paste into GitHub → Settings → SSH and GPG keys → New SSH key
ssh -T git@github.com   # should say: "Hi <you>! You've successfully authenticated..."
```

**Run the bootstrap (replace private repo if different)**
```bash
sudo GIT_URL=git@github.com:harprit-s/homelab.git bash -c \
"curl -fsSL https://raw.githubusercontent.com/harprit-s/homelabpublic/main/scripts/bootstrap_homelab_ubuntu.sh | bash"
```

> Defaults: “auto” mode installs Docker only if missing, then deploys.  
> - Force re-install Docker: `MODE=fresh` (env)  
> - Skip Docker install (just stacks): `MODE=stacks`

**Daily use**
```bash
cd /opt/homelab
git pull --rebase
sudo bash scripts/deploy_all.sh update   # update & redeploy
sudo bash scripts/deploy_all.sh down     # stop all stacks
sudo bash scripts/deploy_all.sh up       # start all stacks
```

---

### B) Manual path (explicit steps)

#### 1) Install Docker + Compose (official)
```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker "$USER"   # log out/in to use docker without sudo
```

#### 2) Clone your **private** homelab repo to the server
```bash
sudo mkdir -p /opt && cd /opt
sudo git clone git@github.com:harprit-s/homelab.git
sudo chown -R "$USER":"$USER" homelab
cd homelab
```

#### 3) Create real `.env` files from examples
```bash
for ex in stacks/*/.env.example; do real="${ex%.example}"; [ -f "$real" ] || cp "$ex" "$real"; done
nano stacks/<app>/.env    # edit ports, TZ, etc.
```

#### 4) Deploy everything
```bash
sudo bash scripts/deploy_all.sh update
```

#### 5) Manage later
```bash
sudo bash scripts/deploy_all.sh down   # stop/remove containers (data stays)
sudo bash scripts/deploy_all.sh up     # start
```

---

## Troubleshooting

- **Permission denied in `/opt/homelab`**
  ```bash
  sudo chown -R "$(logname)":"$(logname)" /opt/homelab
  ```
- **Git identity when committing from scripts**
  ```bash
  git -C /opt/homelab config user.name  "Your Name"
  git -C /opt/homelab config user.email "your-noreply@users.noreply.github.com"
  ```
- **Compose missing env vars** → ensure a real `.env` exists next to each `compose.yaml`, or let `deploy_all.sh` auto-copy from `.env.example`.
- **Stop Docker like “turn off service”**
  ```bash
  sudo systemctl stop docker docker.socket containerd
  sudo systemctl start containerd docker
  ```

---
# Single‑Stack Management Cheatsheet

Use these commands to manage **one stack** at a time in your homelab.

> Run them from your repo root (e.g., `/opt/homelab`).  
> Replace `<stackname>` with the folder under `stacks/` (e.g., `chromium`, `webtop`).  
> The `--env-file` flag ensures your stack’s `.env` is loaded even when you run from the repo root.

---

## Stop a single stack
```bash
docker compose \
  -f stacks/<stackname>/compose.yaml \
  --env-file stacks/<stackname>/.env \
  down
```
- Gracefully stops containers in that stack and removes them.
- **Data is kept** (volumes/bind mounts are not deleted).

---

## Update a single stack (pull latest image(s) + restart)
```bash
docker compose \
  -f stacks/<stackname>/compose.yaml \
  --env-file stacks/<stackname>/.env \
  pull

docker compose \
  -f stacks/<stackname>/compose.yaml \
  --env-file stacks/<stackname>/.env \
  up -d
```
- Downloads the newest images, then recreates containers with those images.

---

## Start a single stack
```bash
docker compose \
  -f stacks/<stackname>/compose.yaml \
  --env-file stacks/<stackname>/.env \
  up -d
```
- Starts the stack in the background using current images/config.

---

## Remove (Destroy) a single stack
```bash
docker compose \
  -f stacks/<stackname>/compose.yaml \
  --env-file stacks/<stackname>/.env \
  down -v
```
- Stops and removes containers **and their named volumes** for this stack.
- ⚠ **Warning:** `-v` deletes data in **named volumes**.  
  Bind mounts like `/opt/containers/<stackname>/config:/config` remain on disk; delete them manually if you want a full wipe:
  ```bash
  sudo rm -rf /opt/containers/<stackname>/config
  ```


