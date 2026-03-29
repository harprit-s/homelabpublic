# Homelab Public Bootstrap

This guide helps you:

1. Enable SSH on Ubuntu
2. Deploy your Docker homelab from a **private** GitHub repo via a one-command bootstrap (or manual steps)
3. Manage individual stacks
4. Expose services securely with Cloudflare Tunnel

> **Assumptions**
> - Ubuntu 22.04+ with sudo access
> - Your **private** repo holds your Compose stacks
> - You'll run these commands **on the Ubuntu server** you're setting up

---

## 1. Enabling SSH on Ubuntu

### Install SSH and networking tools

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

### Recommended: Use SSH keys (and harden)

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

## 2. Deploying Everything (Git-driven Homelab)

You have two paths: **A (one-command bootstrap)** or **B (manual)**.

### A) One-command bootstrap (automatic)

**What it does:**
- Installs Docker + Compose (if missing)
- Clones/updates your **private** homelab repo (Compose stacks)
- Auto-creates any missing `.env` from `.env.example`
- Pulls images and brings stacks up

**Prepare: add an SSH deploy key on the server (one-time)**

```bash
ssh-keygen -t ed25519 -C "homelab" -f ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub
# Paste into GitHub → Settings → SSH and GPG keys → New SSH key
ssh -T git@github.com   # should say: "Hi <you>! You've successfully authenticated..."
```

**Run the bootstrap** (replace private repo if different):

```bash
sudo GIT_URL=git@github.com:harprit-s/homelab.git bash -c \
"curl -fsSL https://raw.githubusercontent.com/harprit-s/homelabpublic/main/scripts/bootstrap_homelab_ubuntu.sh | bash"
```

> **Bootstrap Modes**
>
> Control the script's behavior by setting the `MODE` environment variable before running:
>
> | Mode | Behavior |
> |------|----------|
> | `auto` (default) | Installs Docker if missing, then deploys |
> | `fresh` | Forces a full Docker re-install |
> | `stacks` | Skips Docker install, only deploys stacks |
>
> Example — force a fresh Docker install:
> ```bash
> sudo GIT_URL=... MODE=fresh bash -c \
> "curl -fsSL ... | bash"
> ```

**Daily use:**

```bash
cd /opt/homelab
git pull --rebase
sudo bash scripts/deploy_all.sh update   # update & redeploy
sudo bash scripts/deploy_all.sh down     # stop all stacks
sudo bash scripts/deploy_all.sh up       # start all stacks
```

---

### B) Manual path (explicit steps)

#### 1. Install Docker + Compose (official)

```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker "$USER"   # log out/in to use docker without sudo
```

#### 2. Clone your **private** homelab repo to the server

```bash
sudo mkdir -p /opt && cd /opt
sudo git clone git@github.com:harprit-s/homelab.git
sudo chown -R "$USER":"$USER" homelab
cd homelab
```

#### 3. Create real `.env` files from examples

```bash
for ex in stacks/*/.env.example; do real="${ex%.example}"; [ -f "$real" ] || cp "$ex" "$real"; done
nano stacks/<app>/.env    # edit ports, TZ, etc.
```

#### 4. Deploy everything

```bash
sudo bash scripts/deploy_all.sh update
```

#### 5. Manage later

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
- **Compose missing env vars** — ensure a real `.env` exists next to each `compose.yaml`, or let `deploy_all.sh` auto-copy from `.env.example`.
- **Stop Docker like "turn off service"**
  ```bash
  sudo systemctl stop docker docker.socket containerd
  sudo systemctl start containerd docker
  ```

---

## 3. Single-Stack Management Cheatsheet

Use these commands to manage **one stack** at a time in your homelab.

> Run them from your repo root (e.g., `/opt/homelab`).
> Replace `<stackname>` with the folder under `stacks/` (e.g., `chromium`, `webtop`).
> The `--env-file` flag ensures your stack's `.env` is loaded even when running from the repo root.

### Stop a single stack

```bash
docker compose \
  -f stacks/<stackname>/compose.yaml \
  --env-file stacks/<stackname>/.env \
  down
```

Gracefully stops and removes containers in that stack. **Data is kept** (volumes/bind mounts are not deleted).

### Update a single stack (pull latest image + restart)

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

Downloads the newest images, then recreates containers with those images.

### Start a single stack

```bash
docker compose \
  -f stacks/<stackname>/compose.yaml \
  --env-file stacks/<stackname>/.env \
  up -d
```

Starts the stack in the background using current images/config.

### Remove (destroy) a single stack

```bash
docker compose \
  -f stacks/<stackname>/compose.yaml \
  --env-file stacks/<stackname>/.env \
  down -v
```

Stops and removes containers **and their named volumes** for this stack.

> **Warning:** `-v` deletes data in **named volumes**. Bind mounts (e.g., `/opt/containers/<stackname>/config:/config`) remain on disk. Delete them manually for a full wipe:
> ```bash
> sudo rm -rf /opt/containers/<stackname>/config
> ```

---

## 4. Exposing Services with Cloudflare Tunnel

Cloudflare Tunnel (formerly Argo Tunnel) lets you publish services from your home network securely. It creates an **outbound-only** connection to Cloudflare — no open router ports or Dynamic DNS required.

### Prerequisites

- A Cloudflare account with a domain pointed to Cloudflare nameservers
- A Zero Trust dashboard instance (free for up to 50 users)
- A machine on your home network to act as the connector (Linux, Windows, macOS, or Docker)

---

### 4.1 Set Up the Tunnel

The easiest way is via the Cloudflare Zero Trust Dashboard:

1. Navigate to **Networks > Tunnels**
2. Click **Create a tunnel** and select **Cloudflared**
3. Give your tunnel a name (e.g., `Home-Server`)
4. Install the connector — Cloudflare provides a command to run on your home machine that installs the `cloudflared` daemon and authenticates it

> **Tip:** Running `cloudflared` in Docker is often the cleanest approach for home servers.

---

### 4.2 Route Your Traffic

Once the tunnel status shows **Active**, configure where traffic is sent:

#### Option A: Public Hostname (access via domain)

Exposes a specific service (e.g., a web app) at a subdomain:

1. Go to the **Public Hostname** tab
2. Set **Subdomain** (e.g., `myserver`) and **Domain** (e.g., `yourdomain.com`)
3. Set **Service** to the protocol (usually `HTTP`) and the private IP + port (e.g., `192.168.1.50:8080`)

#### Option B: Private Network (VPN-style access)

Gives access to your entire home subnet without making individual services public:

1. Go to the **Private Network** tab
2. Add your IP range (e.g., `192.168.1.0/24`)
3. Install the **Cloudflare WARP** client on remote devices to reach private IPs

---

### 4.3 Layer on Security

Even with a public hostname, don't leave it open to the world:

1. Go to **Access > Applications** and click **Add an application**
2. Select **Self-hosted**
3. Enter the subdomain from step 4.2
4. Create a **Policy** to restrict access:
   - **Action:** Allow
   - **Include:** Emails (your specific email) or GitHub/Google authentication

> **SSL Note:** Cloudflare handles TLS termination. If your local service uses a self-signed certificate, enable **No TLS Verify** in the tunnel's HTTP Settings.

---

### 4.4 Securing Your Tunnel with Email OTP

Cloudflare includes One-Time PIN (OTP) via email as the simplest authentication method.

#### Step 1: Configure your identity provider

1. In the Zero Trust Dashboard, go to **Settings > Authentication**
2. Confirm **One-time PIN** is enabled under Login methods
3. *(Optional)* Click **Add new** to add Google or GitHub as an alternative provider

#### Step 2: Create an application

1. Go to **Access > Applications > Add an application**
2. Select **Self-hosted**
3. Fill in:
   - **Application name:** e.g., `Home Server`
   - **Domain:** the exact subdomain + domain from your tunnel (e.g., `myserver.yourdomain.com`)
4. Click **Next**

#### Step 3: Add an access policy

1. **Policy name:** e.g., `Allow Me Only`
2. **Action:** Allow
3. **Rules:**
   - **Selector:** Emails
   - **Value:** your personal email address
4. Click **Next**, then **Add application**

**How it works:**

1. You navigate to `myserver.yourdomain.com`
2. Cloudflare shows a login page
3. You enter your email
4. Cloudflare sends a 6-digit OTP to your inbox
5. You enter the code and gain access

> **Pro tip — Bypass rule for home Wi-Fi:**
> Add a second policy to skip the OTP when you're on your home network:
> - **Action:** Bypass
> - **Selector:** IP Ranges
> - **Value:** your home network's public IP address
