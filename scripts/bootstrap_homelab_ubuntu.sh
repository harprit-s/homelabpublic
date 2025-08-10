#!/usr/bin/env bash
# bootstrap_homelab_ubuntu.sh
# Secure public bootstrap: installs Docker (if needed), clones a *private* homelab repo via SSH,
# auto-creates .env from .env.example, and deploys stacks.
#
# Usage:
#   sudo GIT_URL=git@github.com:harprit-s/homelab.git bash -c \
#   "curl -fsSL https://raw.githubusercontent.com/harprit-s/homelabpublic/main/scripts/bootstrap_homelab_ubuntu.sh | bash"
#
# Config via env:
#   MODE=auto|fresh|stacks   # default: auto  (install Docker if missing)
#   BRANCH=main              # default: main
#   HOMELAB_DIR=/opt/homelab # default: /opt/homelab
#   HARD_RESET=1|0           # default: 1 (git reset --hard), 0 = pull --rebase
#
set -Eeuo pipefail

# ---- Config (no secrets here) ----
MODE="${MODE:-auto}"
GIT_URL="${GIT_URL:-git@github.com:harprit-s/homelab.git}"
BRANCH="${BRANCH:-main}"
HOMELAB_DIR="${HOMELAB_DIR:-/opt/homelab}"
HARD_RESET="${HARD_RESET:-1}"
RUN_AS="${SUDO_USER:-$USER}"

msg(){ printf "\033[1;32m==> %s\033[0m\n" "$*"; }
warn(){ printf "\033[1;33m==> %s\033[0m\n" "$*"; }
err(){ printf "\033[1;31m[ERROR]\033[0m %s\n" "$*" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }
require_root(){ [[ $EUID -eq 0 ]] || err "Run as root: sudo bash $0"; }
on_err(){ err "Bootstrap failed on line $1"; }
trap 'on_err $LINENO' ERR

require_root

# ---- OS sanity check ----
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || warn "Non-Ubuntu OS detected (${ID:-unknown}); continuing anyway."
fi

# ---- Minimal deps (no secrets) ----
msg "Installing minimal prerequisites (curl, git, gnupg, ca-certificates, lsb-release)..."
apt-get update -y
apt-get install -y curl git gnupg ca-certificates lsb-release apt-transport-https

# ---- Validate GIT_URL ----
case "$GIT_URL" in
  git@github.com:harprit-s/*) : ;;  # allowed
  *) err "Refusing GIT_URL: $GIT_URL. Use SSH URL under 'harprit-s', e.g. git@github.com:harprit-s/homelab.git";;
esac

# ---- Pin GitHub host key ----
install -d -m 700 "/home/$RUN_AS/.ssh" || true
chown -R "$RUN_AS":"$RUN_AS" "/home/$RUN_AS/.ssh"
if ! sudo -u "$RUN_AS" -H ssh-keygen -F github.com >/dev/null 2>&1; then
  msg "Adding github.com to known_hosts"
  sudo -u "$RUN_AS" -H bash -c 'ssh-keyscan -H github.com >> ~/.ssh/known_hosts'
fi

# ---- Docker install ----
docker_present(){ have docker && have systemctl && systemctl is-active docker >/dev/null 2>&1; }

install_docker(){
  msg "Installing Docker Engine + Compose..."
  apt-get update -y
  for p in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    dpkg -l | awk '{print $2}' | grep -qx "$p" && apt-get remove -y "$p" || true
  done
  apt-get autoremove -y || true

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  arch="$(dpkg --print-architecture)"
  codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
  echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${codename} stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  install -d -m 0755 /etc/docker
  cat > /etc/docker/daemon.json <<'JSON'
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "storage-driver": "overlay2"
}
JSON

  systemctl daemon-reload
  systemctl enable --now docker

  if [[ -n "${SUDO_USER:-}" ]]; then
    id -nG "$SUDO_USER" | grep -qw docker || usermod -aG docker "$SUDO_USER" || true
    warn "Log out/in (or run 'newgrp docker') for non-sudo docker access."
  fi
}

case "$MODE" in
  fresh) install_docker ;;
  auto)  docker_present || install_docker ;;
  stacks) msg "Skipping Docker install (MODE=stacks)" ;;
  *) err "Unknown MODE: $MODE (use auto|fresh|stacks)" ;;
esac

# ---- Clone or update homelab repo ----
install -d -m 0755 "$(dirname "$HOMELAB_DIR")"
chown -R "$RUN_AS":"$RUN_AS" "$(dirname "$HOMELAB_DIR")"
if [[ -d "$HOMELAB_DIR/.git" ]]; then
  msg "Updating homelab repo at $HOMELAB_DIR (branch: $BRANCH)"
  sudo -u "$RUN_AS" -H git -C "$HOMELAB_DIR" fetch origin "$BRANCH"
  if [[ "$HARD_RESET" == "1" ]]; then
    sudo -u "$RUN_AS" -H git -C "$HOMELAB_DIR" reset --hard "origin/$BRANCH"
  else
    sudo -u "$RUN_AS" -H git -C "$HOMELAB_DIR" pull --rebase origin "$BRANCH"
  fi
else
  msg "Cloning $GIT_URL → $HOMELAB_DIR (branch: $BRANCH)"
  sudo -u "$RUN_AS" -H git clone --branch "$BRANCH" "$GIT_URL" "$HOMELAB_DIR"
fi

# ---- Ensure deploy script exists ----
if [[ ! -x "$HOMELAB_DIR/scripts/deploy_all.sh" ]]; then
  warn "deploy_all.sh not found; creating a minimal one."
  install -d -m 0755 "$HOMELAB_DIR/scripts"
  cat > "$HOMELAB_DIR/scripts/deploy_all.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
ACTION="${1:-update}"
command -v docker >/dev/null || { echo "docker missing"; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "'docker compose' plugin required"; exit 1; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
shopt -s nullglob
for STACK in stacks/*; do
  [ -d "$STACK" ] || continue
  COMPOSE="$STACK/compose.yaml"
  [ -f "$COMPOSE" ] || continue
  [ -f "$STACK/.env" ] || { [ -f "$STACK/.env.example" ] && cp "$STACK/.env.example" "$STACK/.env" && echo "Created $STACK/.env"; }
  ENVFILE="$STACK/.env"
  CMD=(docker compose -f "$COMPOSE"); [ -f "$ENVFILE" ] && CMD+=(--env-file "$ENVFILE")
  case "$ACTION" in
    up)      "${CMD[@]}" up -d ;;
    down)    "${CMD[@]}" down ;;
    pull)    "${CMD[@]}" pull ;;
    update)  "${CMD[@]}" pull; "${CMD[@]}" up -d ;;
    *) echo "Unknown action: $ACTION"; exit 1 ;;
  esac
done
EOS
  chmod +x "$HOMELAB_DIR/scripts/deploy_all.sh"
fi

# ---- Auto-create .env from example ----
msg "Ensuring .env files exist for each stack..."
sudo -u "$RUN_AS" -H bash -c "
  cd '$HOMELAB_DIR'
  shopt -s nullglob
  for ex in stacks/*/.env.example; do
    real=\${ex%.example}
    if [ ! -f \"\$real\" ]; then
      cp \"\$ex\" \"\$real\"
      echo \"Created: \$real\"
      chmod 600 \"\$real\" || true
    fi
  done
"

# ---- Deploy all stacks ----
msg "Deploying stacks..."
bash "$HOMELAB_DIR/scripts/deploy_all.sh" update || warn "Deploy returned warnings."

msg "Bootstrap complete."
echo "Repo:   $HOMELAB_DIR  (branch: $BRANCH)"
echo "Mode:   $MODE"
