#!/usr/bin/env bash
set -euo pipefail

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 Starte AirScan Setup...${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURRENT_USER=$(whoami)
INSTALL_DIR="$HOME/scan-web"

# 1. System-Pakete prüfen
echo "📦 Prüfe System-Pakete..."
PACKAGES=(python3 python3-pip python3-venv python3-pil sane-utils hplip imagemagick ghostscript ocrmypdf tesseract-ocr-deu)
MISSING_PACKAGES=()
for pkg in "${PACKAGES[@]}"; do
    if ! dpkg -l | grep -q "^ii  $pkg " 2>/dev/null; then MISSING_PACKAGES+=("$pkg"); fi
done

if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    sudo apt update && sudo apt install -y "${MISSING_PACKAGES[@]}"
fi

# 2. Verzeichnisse & Dateien
mkdir -p "$INSTALL_DIR/scripts"
mkdir -p "$HOME/scans"
cp -r "$SCRIPT_DIR/src/"* "$INSTALL_DIR/"
cp "$SCRIPT_DIR/scripts/airscan.sh" "$INSTALL_DIR/scripts/airscan.sh"
chmod +x "$INSTALL_DIR/scripts/airscan.sh"
# Symlink für Bequemlichkeit
ln -sf "$INSTALL_DIR/scripts/airscan.sh" "$HOME/airscan.sh"

# 3. Python venv
echo "🐍 Bereite Python Virtual Environment vor..."
cd "$INSTALL_DIR"
python3 -m venv venv
./venv/bin/pip install --upgrade pip -q
./venv/bin/pip install fastapi uvicorn[standard] python-multipart pillow -q

# 4. Systemd Service (System-weit)
echo "⚙️  Erstelle System-Service (scan-web.service)..."
sudo tee /etc/systemd/system/scan-web.service > /dev/null << EOFSERVICE
[Unit]
Description=Scanner Web Interface
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
Group=$CURRENT_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/venv/bin/python -m uvicorn app:app --host 0.0.0.0 --port 5000
Restart=always
Environment="PATH=$INSTALL_DIR/venv/bin:/usr/local/bin:/usr/bin:/bin"

[Install]
WantedBy=multi-user.target
EOFSERVICE

sudo systemctl daemon-reload
sudo systemctl enable scan-web
sudo systemctl restart scan-web

echo -e "${GREEN}✨ Setup erfolgreich!${NC}"
echo "App: http://$(hostname -I | awk '{print $1}'):5000"
