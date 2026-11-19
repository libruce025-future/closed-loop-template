#!/usr/bin/env bash
# One-time (idempotent) ECS bootstrap. Run from a checkout of this repo:
#   sudo bash deploy/bootstrap-ecs.sh
set -Eeuo pipefail

APP_BASE="${APP_BASE:-/opt/closed-loop}"
DEPLOY_USER="${DEPLOY_USER:-deploy}"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ "${EUID}" -eq 0 ]] || { echo "run as root: sudo bash deploy/bootstrap-ecs.sh" >&2; exit 1; }

# --- docker ---------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  if command -v dnf >/dev/null 2>&1; then
    dnf install -y docker
  elif command -v apt-get >/dev/null 2>&1; then
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io
  else
    echo "unsupported distro: install docker manually" >&2
    exit 1
  fi
fi
systemctl enable --now docker

# --- deploy user (NOT in the docker group: docker == root) -----------------
id "$DEPLOY_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$DEPLOY_USER"
install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"
touch "/home/$DEPLOY_USER/.ssh/authorized_keys"
chmod 600 "/home/$DEPLOY_USER/.ssh/authorized_keys"
chown "$DEPLOY_USER:$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh/authorized_keys"

# --- app layout ------------------------------------------------------------
install -d -m 755 "$APP_BASE" "$APP_BASE/releases" "$APP_BASE/scripts"
install -d -m 755 "$APP_BASE/.docker"
install -m 755 "$SRC_DIR/../scripts/deploy-remote.sh" "$APP_BASE/scripts/deploy-remote.sh"
install -m 644 "$SRC_DIR/docker-compose.prod.yml" "$APP_BASE/compose.yml"
install -m 644 "$SRC_DIR/Caddyfile" "$APP_BASE/Caddyfile"

install -m 600 -n "$SRC_DIR/deploy.env.example" "$APP_BASE/deploy.env"
install -m 600 -n "$SRC_DIR/app.env.example" "$APP_BASE/app.env"

# --- deploy-ctl (root-owned, the only sudo-allowed verb) -------------------
install -m 755 "$SRC_DIR/deploy-ctl" /usr/local/bin/deploy-ctl
cat > /etc/sudoers.d/closed-loop-deploy <<SUDO
$DEPLOY_USER ALL=(root) NOPASSWD: /usr/local/bin/deploy-ctl
SUDO
chmod 440 /etc/sudoers.d/closed-loop-deploy
visudo -cf /etc/sudoers.d/closed-loop-deploy >/dev/null

cat <<EOF

Bootstrap done. Remaining manual steps:

1. Authorize the deploy key (from your machine):
     ssh-copy-id -i ~/.ssh/closed-loop_deploy.pub $DEPLOY_USER@<ECS_HOST>
   Then on this host:
     sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
     sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
     echo "AllowUsers $DEPLOY_USER" >> /etc/ssh/sshd_config
     sshd -t && systemctl reload sshd

2. Fill in registry/domain:
     sudoedit $APP_BASE/deploy.env
   Fill in secrets:
     sudoedit $APP_BASE/app.env

3. Log this host into the registry once (pull credential):
     sudo docker login <IMAGE_REGISTRY>

4. Verify:  sudo /usr/local/bin/deploy-ctl status
EOF
