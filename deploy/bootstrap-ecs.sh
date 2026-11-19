#!/usr/bin/env bash
# One-time (idempotent) ECS bootstrap for the static nginx variant.
# Run from a checkout of this repo:  sudo bash deploy/bootstrap-ecs.sh
set -Eeuo pipefail

APP_BASE="${APP_BASE:-/opt/closed-loop}"
DEPLOY_USER="${DEPLOY_USER:-deploy}"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SRC_DIR/.." && pwd)"

[[ "${EUID}" -eq 0 ]] || { echo "run as root: sudo bash deploy/bootstrap-ecs.sh" >&2; exit 1; }

if command -v dnf >/dev/null 2>&1; then
  dnf install -y nginx rsync curl
elif command -v apt-get >/dev/null 2>&1; then
  apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y nginx rsync curl
else
  echo "unsupported distro: install nginx, rsync and curl manually" >&2
  exit 1
fi

id "$DEPLOY_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$DEPLOY_USER"
install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"
touch "/home/$DEPLOY_USER/.ssh/authorized_keys"
chmod 600 "/home/$DEPLOY_USER/.ssh/authorized_keys"
chown "$DEPLOY_USER:$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh/authorized_keys"

install -d -m 755 "$APP_BASE" "$APP_BASE/scripts"
install -d -m 755 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$APP_BASE/releases"
install -m 755 "$ROOT_DIR/scripts/deploy-remote.sh" "$APP_BASE/scripts/deploy-remote.sh"
install -m 644 "$SRC_DIR/nginx.conf" "$APP_BASE/nginx.conf"
install -m 755 "$SRC_DIR/deploy-ctl" /usr/local/bin/deploy-ctl

cat > /etc/sudoers.d/closed-loop-deploy <<SUDO
$DEPLOY_USER ALL=(root) NOPASSWD: /usr/local/bin/deploy-ctl
SUDO
chmod 440 /etc/sudoers.d/closed-loop-deploy
visudo -cf /etc/sudoers.d/closed-loop-deploy >/dev/null

install -m 644 "$SRC_DIR/nginx.conf" /etc/nginx/conf.d/closed-loop.conf
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable nginx
systemctl reload nginx

cat <<EOF

Bootstrap done. Remaining manual steps:

1. Authorize the deploy key (from your machine):
     ssh-copy-id -i ~/.ssh/closed-loop_deploy.pub $DEPLOY_USER@<ECS_HOST>
   Then on this host:
     sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
     sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
     echo "AllowUsers $DEPLOY_USER" >> /etc/ssh/sshd_config
     sshd -t && systemctl reload sshd

2. Optional HTTPS:
     apt-get install -y certbot python3-certbot-nginx   # or dnf install -y certbot python3-certbot-nginx
     certbot --nginx -d your.domain

3. Verify after the first deploy:
     sudo /usr/local/bin/deploy-ctl status
     curl -fsS http://127.0.0.1:8080/version.json
EOF
