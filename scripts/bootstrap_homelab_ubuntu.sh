#!/usr/bin/env bash
set -euo pipefail

MODE="${MODE:-auto}"   # auto | fresh | stacks
GIT_URL="${GIT_URL:-git@github.com:harprit-s/homelab.git}"
TARGET_DIR="/opt/homelab"
RUN_AS="${SUDO_USER:-$USER}"

msg(){ printf "\033[1;32m==> %s\033[0m\n" "$*"; }
warn(){ printf "\033[1;33m==> %s\033[0m\n" "$*"; }
err(){ printf "\033[1;31m[ERROR]\033[0m %s\n" "$*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || err "Missing: $1"; }

# -------------------------------------------------
# 1. Install Docker if needed or requested
# -------------------------------------------------
install_docker() {
  msg "Installing Docker..."
  sudo apt-get remove -y docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc || true
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc >/dev/null
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

if [[ "$MODE" == "fresh" ]]; then
  install_docker
elif [[ "$MODE" == "auto" ]]; then
  if ! command -v docker >/dev/null 2>&1; then
    install_docker
  else
    msg "Docker already installed — skipping."
  fi
else
  msg "Skipping Docker install (MODE=$MODE)"
fi

# -------------------------------------------------
# 2. Clone or update homelab repo
# -------------------------------------------------
need git
sudo mkdir -p "$TARGET_DIR"
sudo chown -R "$RUN_AS":"$RUN_AS" "$TARGET_DIR"

if [[ -d "$TARGET_DIR/.git" ]]; then
  msg "Updating existing repo at $TARGET_DIR"
  sudo -u "$RUN_AS" -H git -C "$TARGET_DIR" pull --rebase || warn "git pull failed"
else
  msg "Cloning repo from $GIT_URL"
  sudo -u "$RUN_AS" -H git clone "$GIT_URL" "$TARGET_DIR" || err "Failed to clone repo"
fi

# -------------------------------------------------
# 3. Auto-create .env from .env.example
# -------------------------------------------------
msg "Checking for missing .env files..."
sudo -u "$RUN_AS" -H bash -c "
  cd '$TARGET_DIR'
  for ex in stacks/*/.env.example; do
    real=\"\${ex%.example}\"
    if [ ! -f \"\$real\" ]; then
      cp \"\$ex\" \"\$real\"
      echo \"Created: \$real\"
    fi
  done
"

# -------------------------------------------------
# 4. Deploy all stacks
# -------------------------------------------------
msg "Deploying stacks..."
sudo bash "$TARGET_DIR/scripts/deploy_all.sh" update

msg "Bootstrap complete!"
