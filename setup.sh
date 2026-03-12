#!/usr/bin/env bash
set -euo pipefail

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Banner
echo -e "${BLUE}"
cat << "BANNER"
 █████  ██ ██████  ███████  ██████  █████  ███    ██       ██     ██ ███████ ██████  
██   ██ ██ ██   ██ ██      ██      ██   ██ ████   ██       ██     ██ ██      ██   ██ 
███████ ██ ██████  ███████ ██      ███████ ██ ██  ██ █████ ██  █  ██ █████   ██████  
██   ██ ██ ██   ██      ██ ██      ██   ██ ██  ██ ██       ██ ███ ██ ██      ██   ██ 
██   ██ ██ ██   ██ ███████  ██████ ██   ██ ██   ████        ███ ███  ███████ ██████  
                                                                                                                                   
  Scanner Web Interface - Installation
BANNER
echo -e "${NC}"
echo ""

# Pfad-Erkennung
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURRENT_USER=$(whoami)
HOME_DIR="$HOME"
INSTALL_DIR="$HOME_DIR/scan-web"
SERVICE_PORT=5000

if [[ ! -f "$SCRIPT_DIR/src/app.py" ]]; then
    echo -e "${RED}❌ Fehler: Bitte führe das Skript aus dem Repository-Verzeichnis aus${NC}"
    exit 1
fi

echo -e "${BLUE}📋 System-Voraussetzungen (Prerequisites):${NC}"
echo "-------------------------------------------------------"
echo "Das Programm benötigt folgende System-Komponenten:"
echo -e "1. ${YELLOW}sane-utils${NC}      (Kommunikation mit AirScan-Geräten)"
echo -e "2. ${YELLOW}hplip${NC}           (HP-spezifische Funktionen/hp-scan)"
echo -e "3. ${YELLOW}imagemagick${NC}     (Konvertierung von Scans in PDF)"
echo -e "4. ${YELLOW}ghostscript${NC}     (PDF-Komprimierung)"
echo -e "5. ${YELLOW}python3-venv${NC}    (Isolierte Python-Umgebung)"
echo -e "6. ${YELLOW}ocrmypdf${NC}        (Optional: Texterkennung/OCR)"
echo "-------------------------------------------------------"
echo ""

echo "📋 Konfiguration:"
echo "   User:           $CURRENT_USER"
echo "   Install-Dir:    $INSTALL_DIR"
echo "   Service-Port:   $SERVICE_PORT"
echo ""

# Bestätigung
read -p "Installation starten? [J/n] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[JjYy]$ ]] && [[ ! -z $REPLY ]]; then
    echo "Installation abgebrochen."
    exit 0
fi

# 1. System-Abhängigkeiten prüfen
echo ""
echo "📦 Prüfe System-Abhängigkeiten..."
PACKAGES=(python3 python3-pip python3-venv python3-pil sane-utils hplip imagemagick ghostscript ocrmypdf tesseract-ocr-deu)
MISSING_PACKAGES=()

for pkg in "${PACKAGES[@]}"; do
    if ! dpkg -l | grep -q "^ii  $pkg " 2>/dev/null; then
        MISSING_PACKAGES+=("$pkg")
    fi
done

if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Installiere fehlende Pakete: ${MISSING_PACKAGES[*]}${NC}"
    sudo apt update
    sudo apt install -y "${MISSING_PACKAGES[@]}"
else
    echo -e "${GREEN}✅ System-Abhängigkeiten OK${NC}"
fi

# 2. Installations-Verzeichnis vorbereiten
echo ""
echo "📁 Erstelle Verzeichnisse..."
mkdir -p "$INSTALL_DIR/scripts"
mkdir -p "$HOME_DIR/scans"
echo -e "${GREEN}✅ Verzeichnisse bereit${NC}"

# 3. Dateien kopieren
echo ""
echo "📋 Kopiere App-Dateien..."
cp -r "$SCRIPT_DIR/src/"* "$INSTALL_DIR/"
cp "$SCRIPT_DIR/scripts/airscan.sh" "$INSTALL_DIR/scripts/airscan.sh"
chmod +x "$INSTALL_DIR/scripts/airscan.sh"
# Symlink im Home für einfachen Zugriff
ln -sf "$INSTALL_DIR/scripts/airscan.sh" "$HOME_DIR/airscan.sh"
echo -e "${GREEN}✅ Dateien kopiert und Berechtigungen gesetzt${NC}"

# 4. .env Datei erstellen falls nicht vorhanden
if [[ ! -f "$INSTALL_DIR/.env" ]]; then
    echo ""
    echo "⚙️ Erstelle Standard .env Konfiguration..."
    echo 'DEVICE_URI="mock"' > "$INSTALL_DIR/.env"
    echo -e "${YELLOW}⚠️  Standard-URI auf 'mock' gesetzt. Bitte in $INSTALL_DIR/.env anpassen.${NC}"
fi

# 5. Python Virtual Environment
echo ""
echo "🐍 Erstelle Python Virtual Environment..."
cd "$INSTALL_DIR"
python3 -m venv venv
./venv/bin/pip install --upgrade pip -q
if [[ -f "$SCRIPT_DIR/requirements.txt" ]]; then
    ./venv/bin/pip install -r "$SCRIPT_DIR/requirements.txt" -q
else
    ./venv/bin/pip install fastapi uvicorn[standard] python-multipart pillow -q
fi
echo -e "${GREEN}✅ Python-Umgebung bereit${NC}"

# 6. Systemd Service (System-weit)
echo ""
echo "⚙️  Richte Systemd Service ein..."
sudo tee /etc/systemd/system/scan-web.service > /dev/null << EOFSERVICE
[Unit]
Description=Scanner Web Interface
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
Group=$CURRENT_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/venv/bin/python -m uvicorn app:app --host 0.0.0.0 --port $SERVICE_PORT
Restart=always
RestartSec=10
Environment="PATH=$INSTALL_DIR/venv/bin:/usr/local/bin:/usr/bin:/bin"
Environment="HOME=$HOME_DIR"

[Install]
WantedBy=multi-user.target
EOFSERVICE

sudo systemctl daemon-reload
sudo systemctl enable scan-web
sudo systemctl restart scan-web
echo -e "${GREEN}✅ Service aktiviert und gestartet${NC}"

# 7. Netzwerk-Informationen & Abschluss
echo ""
IP_ADDR=$(hostname -I | awk '{print $1}')

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                                                        ║${NC}"
echo -e "${BLUE}║  ${GREEN}✨ Installation erfolgreich abgeschlossen! ✨${BLUE}          ║${NC}"
echo -e "${BLUE}║                                                        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "📱 Zugriff auf die Scanner-App:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "   ${GREEN}Lokal:${NC}        http://localhost:$SERVICE_PORT"
echo -e "   ${GREEN}Netzwerk:${NC}     http://$IP_ADDR:$SERVICE_PORT"
echo ""
echo "📋 Nützliche Befehle:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   Status anzeigen:    sudo systemctl status scan-web"
echo "   Logs anzeigen:      sudo journalctl -u scan-web -f"
echo "   Konfiguration:      nano $INSTALL_DIR/.env"
echo ""
echo -e "${GREEN}Viel Erfolg mit deinem Scanner! 🖨️${NC}"
echo ""
