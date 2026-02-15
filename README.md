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

> **Bootstrap Modes**
>
> You can control the script's behavior by setting the `MODE` environment variable.
>
> - **`auto` (Default):** Installs Docker if missing, then deploys. No flag needed.
> - **`fresh`:** Forces a re-install of Docker. Use this if you suspect a problem with your current installation.
> - **`stacks`:** Skips Docker installation and only deploys the stacks. Use this if you manage Docker manually.
>
> **How to use:** Set the `MODE` variable right before the `bash` command. For example, to force a fresh install:
> ```bash
> sudo GIT_URL=... MODE=fresh bash -c \
> "curl -fsSL ... | bash"
> ```

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

---

## 3) Exposing Services with Cloudflare Tunnel

To publish a server or service from your home network using Cloudflare Zero Trust, the best tool for the job is Cloudflare Tunnel (formerly Argo Tunnel).

This method is highly secure because it creates an outbound-only connection to Cloudflare. This means you don't have to open any ports on your router or deal with Dynamic DNS.

### Prerequisites
A Cloudflare account and a domain pointed to Cloudflare nameservers.

A Zero Trust dashboard instance (free for up to 50 users).

A machine on your home network to act as a "connector" (Linux, Windows, macOS, or Docker).

### 1. Set up the Tunnel
The easiest way to manage this is via the Cloudflare Zero Trust Dashboard:

Navigate to Networks > Tunnels.

Click Create a tunnel and select Cloudflared.

Give your tunnel a name (e.g., "Home-Server").

Install the connector: Cloudflare will provide a command to run on your home machine. This installs the cloudflared daemon and authenticates it.

Tip: Running this in Docker is often the cleanest way to manage it on a home server.

### 2. Route Your Traffic
Once the status shows "Active," you need to tell Cloudflare where to send the traffic.

#### Option A: Public Hostname (Access via Domain)
Use this to expose a specific service (like a web server or Plex) to a sub-domain.

Go to the Public Hostname tab.

Subdomain: myserver | Domain: yourdomain.com.

Service: Select the protocol (usually HTTP) and enter the Private IP and Port (e.g., 192.168.1.50:8080).

#### Option B: Private Network (Access via VPN-style)
Use this if you want to access your entire home subnet (e.g., 192.168.1.0/24) securely without making individual services public.

Go to the Private Network tab.

Add your IP range (e.g., 192.168.1.0/24).

You will need the Cloudflare WARP client installed on your remote devices to "see" these private IPs.

### 3. Layer on Security (Crucial Step)
Even if you publish a public hostname, you shouldn't leave it open to the world.

Go to Access > Applications.

Add an application and select Self-hosted.

Enter the subdomain you created in Step 2.

Create a Policy to restrict access. For example:

Action: Allow

Include: Emails (enter your specific email) or GitHub/Google authentication.

⚠️ Security Note
When using Tunnels, Cloudflare handles the SSL/TLS termination. Ensure your local service is working over HTTP/HTTPS correctly before connecting the tunnel. If you use a self-signed certificate locally, you may need to toggle No TLS Verify in the Tunnel's "HTTP Settings."

### 4) Securing Your Tunnel with Email OTP
By default, Cloudflare includes One-Time PIN (OTP) via email, which is the easiest way to start.

#### Step 1: Set up your "Identity Provider"
This is the method users will use to prove who they are.

In the Zero Trust Dashboard, go to Settings > Authentication.

Under Login methods, you’ll see "One-time PIN" is usually enabled by default.

(Optional) If you want to use Google or GitHub instead, click Add new, select the provider, and follow the prompts to link your account.

#### Step 2: Create an "Application"
An Application connects your authentication rules to your specific Tunnel URL.

Go to Access > Applications > Add an application.

Select Self-hosted.

**Application Configuration:**

Application name: Something like "Home Server."

Domain: Enter the exact subdomain and domain you set up in your Tunnel (e.g., myserver.yourdomain.com).

Scroll down and click Next.

#### Step 3: Add an "Access Policy"
This defines who is allowed to pass through the gate.

Policy name: "Allow Me Only."

Action: Ensure this is set to Allow.

**Configure rules:**

Selector: Select Emails.

Value: Type your personal email address.

Tip: You can also use "Emails ending in" for a specific domain (like @yourcompany.com).

Click Next, then scroll to the bottom and click Add application.

**How it works now:**
You type myserver.yourdomain.com into your browser.

Cloudflare intercepts the request and shows a login page.

You enter your email.

Cloudflare sends a 6-digit code to your email.

You enter the code, and only then are you connected to your home server.

**Pro-Tip: The "Bypass" Rule**
If you are at home on your own Wi-Fi, you might not want to enter an OTP every time. You can add a second policy to the same application:

Action: Bypass

Selector: IP Ranges

Value: Your home network's public IP address.

Note: This will let you skip the login screen when you're physically at home.
