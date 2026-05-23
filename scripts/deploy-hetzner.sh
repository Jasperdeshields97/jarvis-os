#!/usr/bin/env bash
# Deploy Jarvis OS to Hetzner Jarvis-01
# Run from local machine: bash scripts/deploy-hetzner.sh
set -euo pipefail

HETZNER="root@87.99.150.125"
REMOTE_DIR="/root/jarvis-os"

echo "→ Syncing repo to Hetzner..."
rsync -az --exclude='.git' --exclude='__pycache__' --exclude='*.pyc' \
  /tmp/jarvis-os/ "$HETZNER:$REMOTE_DIR/"

echo "→ Installing OpenJarvis on Hetzner..."
ssh "$HETZNER" bash <<'REMOTE'
set -euo pipefail
cd /root/jarvis-os

# Install uv if not present
if ! command -v uv &>/dev/null; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.cargo/bin:$PATH"
fi

# Install with cloud + server + telegram extras
uv pip install -e ".[inference-cloud,server,channel-telegram,tools-search]" \
  --system 2>&1 | tail -5

# Create config dir
mkdir -p /root/.openjarvis

# Copy config (don't overwrite if .env already exists)
cp -n /root/jarvis-os/configs/jasper/config.toml /root/.openjarvis/config.toml 2>/dev/null || true
if [ ! -f /root/.openjarvis/.env ]; then
  cp /root/jarvis-os/configs/jasper/.env.example /root/.openjarvis/.env
  echo "⚠  Fill in /root/.openjarvis/.env with real values"
fi

echo "✓ Install complete"
REMOTE

echo "→ Installing systemd service..."
ssh "$HETZNER" bash <<'REMOTE'
cat > /etc/systemd/system/jarvis-os.service <<'SVC'
[Unit]
Description=Jarvis OS — Personal AI Backend
After=network.target docker.service
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/jarvis-os
EnvironmentFile=/root/.openjarvis/.env
ExecStart=/usr/local/bin/jarvis serve --config /root/.openjarvis/config.toml
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
echo "✓ Service installed — start with: systemctl start jarvis-os"
echo "✓ Enable on boot with: systemctl enable jarvis-os"
REMOTE

echo ""
echo "═══════════════════════════════════════"
echo "  Jarvis OS deployed to Hetzner"
echo "  Next steps:"
echo "  1. Fill in /root/.openjarvis/.env"
echo "  2. Set up Google OAuth: jarvis connectors auth gcalendar"
echo "  3. Set up Strava: python3 scripts/strava_auth.py"
echo "  4. systemctl start jarvis-os"
echo "  5. Check logs: journalctl -u jarvis-os -f"
echo "═══════════════════════════════════════"
