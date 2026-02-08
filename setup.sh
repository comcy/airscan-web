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
cat << "EOF"
   _____ _____  _____   _____          _   _ 
  / ____|  __ \|_   _| / ____|   /\   | \ | |
 | |    | |__) | | |  | (___    /  \  |  \| |
 | |    |  ___/  | |   \___ \  / /\ \ | . ` |
 | |____| |     _| |_  ____) |/ ____ \| |\  |
  \_____|_|    |_____||_____//_/    \_\_| \_|
                                              
  Scanner Web Interface - Installation
EOF
echo -e "${NC}"
echo ""

# Prüfe ob Skript aus dem richtigen Verzeichnis ausgeführt wird
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -f "$SCRIPT_DIR/src/app.py" ]]; then
    echo -e "${RED}❌ Fehler: Bitte führe das Skript aus dem Repository-Verzeichnis aus${NC}"
    echo "   cd airscan-web && ./setup.sh"
    exit 1
fi

echo -e "${GREEN}✅ Repository-Verzeichnis erkannt: $SCRIPT_DIR${NC}"
echo ""

# Konfiguration
CURRENT_USER=$(whoami)
HOME_DIR="$HOME"
INSTALL_DIR="$HOME_DIR/scan-web"
SCAN_SCRIPT_SOURCE="$SCRIPT_DIR/scripts/airscan.sh"
SCAN_SCRIPT_TARGET="$HOME_DIR/airscan.sh"
SERVICE_PORT=5000

echo "📋 Konfiguration:"
echo "   User:           $CURRENT_USER"
echo "   Install-Dir:    $INSTALL_DIR"
echo "   Scan-Skript:    $SCAN_SCRIPT_TARGET"
echo "   Port:           $SERVICE_PORT"
echo ""

# Bestätigung
read -p "Installation starten? [J/n] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[JjYy]$ ]] && [[ ! -z $REPLY ]]; then
    echo "Installation abgebrochen."
    exit 0
fi

# 1. System-Abhängigkeiten prüfen und installieren
echo ""
echo "📦 Prüfe System-Abhängigkeiten..."
MISSING_PACKAGES=()

for pkg in python3 python3-pip python3-venv; do
    if ! dpkg -l | grep -q "^ii  $pkg "; then
        MISSING_PACKAGES+=($pkg)
    fi
done

if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Fehlende Pakete: ${MISSING_PACKAGES[*]}${NC}"
    echo "   Installiere..."
    sudo apt update
    sudo apt install -y "${MISSING_PACKAGES[@]}"
fi

# Prüfe ob Pillow-Dependencies vorhanden sind
if ! dpkg -l | grep -q "^ii  python3-pil"; then
    sudo apt install -y python3-pil
fi

echo -e "${GREEN}✅ System-Abhängigkeiten OK${NC}"

# 2. Scan-Skript kopieren (falls vorhanden)
if [[ -f "$SCAN_SCRIPT_SOURCE" ]]; then
    echo ""
    echo "📄 Kopiere Scan-Skript..."
    cp "$SCAN_SCRIPT_SOURCE" "$SCAN_SCRIPT_TARGET"
    chmod +x "$SCAN_SCRIPT_TARGET"
    echo -e "${GREEN}✅ Scan-Skript installiert: $SCAN_SCRIPT_TARGET${NC}"
else
    echo ""
    echo -e "${YELLOW}⚠️  Scan-Skript nicht im Repo gefunden${NC}"
    if [[ ! -f "$SCAN_SCRIPT_TARGET" ]]; then
        echo -e "${RED}❌ Kein Scan-Skript unter $SCAN_SCRIPT_TARGET gefunden!${NC}"
        echo "   Bitte erstelle das Scan-Skript manuell."
        exit 1
    else
        echo -e "${GREEN}✅ Vorhandenes Scan-Skript wird verwendet: $SCAN_SCRIPT_TARGET${NC}"
    fi
fi

# 3. Installations-Verzeichnis vorbereiten
echo ""
echo "📁 Erstelle Installations-Verzeichnis..."
mkdir -p "$INSTALL_DIR"

# 4. Dateien kopieren
echo ""
echo "📋 Kopiere App-Dateien..."
cp -r "$SCRIPT_DIR/src/"* "$INSTALL_DIR/"
echo -e "${GREEN}✅ Dateien kopiert${NC}"

# 5. Python Virtual Environment erstellen
echo ""
echo "🐍 Erstelle Python Virtual Environment..."
cd "$INSTALL_DIR"

if [[ -d "venv" ]]; then
    echo "   Entferne altes venv..."
    rm -rf venv
fi

python3 -m venv venv
source venv/bin/activate

# 6. Python-Pakete installieren
echo ""
echo "📦 Installiere Python-Pakete..."
if [[ -f "$SCRIPT_DIR/requirements.txt" ]]; then
    pip install --upgrade pip -q
    pip install -r "$SCRIPT_DIR/requirements.txt" -q
else
    pip install --upgrade pip -q
    pip install fastapi uvicorn[standard] python-multipart pillow -q
fi
echo -e "${GREEN}✅ Python-Pakete installiert${NC}"

# 7. Icons generieren
echo ""
echo "🎨 Generiere PWA Icons..."
if [[ -f "$INSTALL_DIR/generate-icons.py" ]]; then
    python generate-icons.py
    echo -e "${GREEN}✅ Icons generiert${NC}"
else
    echo -e "${YELLOW}⚠️  Icon-Generator nicht gefunden, überspringe...${NC}"
fi

deactivate

# 8. Systemd Service erstellen
echo ""
echo "⚙️  Erstelle Systemd Service..."

sudo tee /etc/systemd/system/scan-web.service > /dev/null << EOFSERVICE
[Unit]
Description=Scanner PWA Web Interface
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/venv/bin/python -m uvicorn app:app --host 0.0.0.0 --port $SERVICE_PORT
Restart=always
RestartSec=10
Environment="PATH=$INSTALL_DIR/venv/bin:/usr/local/bin:/usr/bin"

[Install]
WantedBy=multi-user.target
EOFSERVICE

echo -e "${GREEN}✅ Service-Datei erstellt${NC}"

# 9. Service aktivieren und starten
echo ""
echo "🚀 Starte Service..."
sudo systemctl daemon-reload
sudo systemctl enable scan-web
sudo systemctl restart scan-web

# Warte kurz und prüfe Status
sleep 2

if sudo systemctl is-active --quiet scan-web; then
    echo -e "${GREEN}✅ Service läuft!${NC}"
else
    echo -e "${RED}❌ Service-Start fehlgeschlagen${NC}"
    echo ""
    echo "Fehler-Logs:"
    sudo journalctl -u scan-web -n 20 --no-pager
    exit 1
fi

# 10. Netzwerk-Informationen
echo ""
IP_ADDR=$(hostname -I | awk '{print $1}')
HOSTNAME=$(hostname)

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                                                        ║${NC}"
echo -e "${BLUE}║  ${GREEN}✨ Installation erfolgreich abgeschlossen! ✨${BLUE}          ║${NC}"
echo -e "${BLUE}║                                                        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "📱 Zugriff auf die Scanner-App:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "   ${GREEN}Lokal:${NC}        http://localhost:$SERVICE_PORT"
echo -e "   ${GREEN}Netzwerk:${NC}     http://$IP_ADDR:$SERVICE_PORT"
echo -e "   ${GREEN}Hostname:${NC}     http://$HOSTNAME.local:$SERVICE_PORT"
echo ""
echo "💡 PWA Installation:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   1. Öffne eine der URLs oben im Browser"
echo "   2. Klicke auf 'Installieren' im grünen Banner"
echo "   3. Die App erscheint auf deinem Homescreen"
echo ""
echo "📋 Nützliche Befehle:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   Status anzeigen:    sudo systemctl status scan-web"
echo "   Service neustarten: sudo systemctl restart scan-web"
echo "   Logs anzeigen:      sudo journalctl -u scan-web -f"
echo "   Service stoppen:    sudo systemctl stop scan-web"
echo ""
echo "📁 Installierte Dateien:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   App-Verzeichnis:  $INSTALL_DIR"
echo "   Scan-Skript:      $SCAN_SCRIPT_TARGET"
echo "   Systemd-Service:  /etc/systemd/system/scan-web.service"
echo "   Scan-Ausgabe:     $HOME_DIR/scans/"
echo ""
echo "🔧 Konfiguration anpassen:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   Scanner-Device:   $SCAN_SCRIPT_TARGET (Zeile mit DEVICE_URI)"
echo "   Port ändern:      /etc/systemd/system/scan-web.service"
echo ""
echo -e "${GREEN}Viel Erfolg mit deinem Scanner! 🖨️${NC}"
echo ""