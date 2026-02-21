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

 █████  ██ ██████  ███████  ██████  █████  ███    ██       ██     ██ ███████ ██████  
██   ██ ██ ██   ██ ██      ██      ██   ██ ████   ██       ██     ██ ██      ██   ██ 
███████ ██ ██████  ███████ ██      ███████ ██ ██  ██ █████ ██  █  ██ █████   ██████  
██   ██ ██ ██   ██      ██ ██      ██   ██ ██  ██ ██       ██ ███ ██ ██      ██   ██ 
██   ██ ██ ██   ██ ███████  ██████ ██   ██ ██   ████        ███ ███  ███████ ██████  
                                                                                                                                   
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

# 1. Alte Installation aufräumen (falls vorhanden)
echo ""
echo "🧹 Räume alte Installation auf..."

# Service stoppen (falls läuft)
if systemctl is-active --quiet scan-web 2>/dev/null; then
    echo "   Stoppe alten Service..."
    sudo systemctl stop scan-web
fi

# Alte Dateien mit falschen Berechtigungen entfernen
if [[ -f "$SCAN_SCRIPT_TARGET" ]]; then
    echo "   Entferne altes Scan-Skript..."
    sudo rm -f "$SCAN_SCRIPT_TARGET"
fi

if [[ -d "$INSTALL_DIR" ]]; then
    # Prüfe Besitzer
    OWNER=$(stat -c '%U' "$INSTALL_DIR" 2>/dev/null || echo "unknown")
    if [[ "$OWNER" != "$CURRENT_USER" ]]; then
        echo "   Entferne Install-Dir mit falschen Berechtigungen (Besitzer: $OWNER)..."
        sudo rm -rf "$INSTALL_DIR"
    fi
fi

# 2. System-Abhängigkeiten prüfen und installieren
echo ""
echo "📦 Prüfe System-Abhängigkeiten..."
MISSING_PACKAGES=()

for pkg in python3 python3-pip python3-venv python3-pil; do
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

echo -e "${GREEN}✅ System-Abhängigkeiten OK${NC}"

# 3. Scan-Skript kopieren (falls vorhanden)
if [[ -f "$SCAN_SCRIPT_SOURCE" ]]; then
    echo ""
    echo "📄 Kopiere Scan-Skript..."
    cp "$SCAN_SCRIPT_SOURCE" "$SCAN_SCRIPT_TARGET"
    chmod +x "$SCAN_SCRIPT_TARGET"
    chown "$CURRENT_USER:$CURRENT_USER" "$SCAN_SCRIPT_TARGET"
    echo -e "${GREEN}✅ Scan-Skript installiert: $SCAN_SCRIPT_TARGET${NC}"
else
    echo ""
    echo -e "${YELLOW}⚠️  Scan-Skript nicht im Repo gefunden${NC}"
    if [[ ! -f "$SCAN_SCRIPT_TARGET" ]]; then
        echo -e "${RED}❌ Kein Scan-Skript unter $SCAN_SCRIPT_TARGET gefunden!${NC}"
        echo "   Bitte erstelle das Scan-Skript manuell oder lege es unter scripts/airscan.sh ab."
        read -p "Trotzdem fortfahren? [j/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[JjYy]$ ]]; then
            exit 1
        fi
    else
        echo -e "${GREEN}✅ Vorhandenes Scan-Skript wird verwendet: $SCAN_SCRIPT_TARGET${NC}"
    fi
fi

# 4. Installations-Verzeichnis vorbereiten
echo ""
echo "📁 Erstelle Installations-Verzeichnis..."
mkdir -p "$INSTALL_DIR"
chown "$CURRENT_USER:$CURRENT_USER" "$INSTALL_DIR"

# 5. Dateien kopieren
echo ""
echo "📋 Kopiere App-Dateien..."
cp -r "$SCRIPT_DIR/src/"* "$INSTALL_DIR/"
chown -R "$CURRENT_USER:$CURRENT_USER" "$INSTALL_DIR"
echo -e "${GREEN}✅ Dateien kopiert${NC}"

# 6. Python Virtual Environment erstellen
echo ""
echo "🐍 Erstelle Python Virtual Environment..."
cd "$INSTALL_DIR"

if [[ -d "venv" ]]; then
    echo "   Entferne altes venv..."
    rm -rf venv
fi

python3 -m venv venv
source venv/bin/activate

# 7. Python-Pakete installieren
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

# 8. Icons generieren
echo ""
echo "🎨 Generiere PWA Icons..."
if [[ -f "$INSTALL_DIR/generate-icons.py" ]]; then
    python generate-icons.py
    echo -e "${GREEN}✅ Icons generiert${NC}"
else
    echo -e "${YELLOW}⚠️  Icon-Generator nicht gefunden, überspringe...${NC}"
fi

deactivate

# 9. Scans-Verzeichnis erstellen
echo ""
echo "📁 Erstelle Scans-Verzeichnis..."
mkdir -p "$HOME_DIR/scans"
chown "$CURRENT_USER:$CURRENT_USER" "$HOME_DIR/scans"
echo -e "${GREEN}✅ Scans-Verzeichnis erstellt: $HOME_DIR/scans${NC}"

# 10. Systemd Service erstellen
echo ""
echo "⚙️  Erstelle Systemd Service..."

sudo tee /etc/systemd/system/scan-web.service > /dev/null << EOFSERVICE
[Unit]
Description=Scanner PWA Web Interface
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
Group=$CURRENT_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/venv/bin/python -m uvicorn app:app --host 0.0.0.0 --port $SERVICE_PORT
Restart=always
RestartSec=10
Environment="PATH=$INSTALL_DIR/venv/bin:/usr/local/bin:/usr/bin"
Environment="HOME=$HOME_DIR"

[Install]
WantedBy=multi-user.target
EOFSERVICE

echo -e "${GREEN}✅ Service-Datei erstellt${NC}"

# 11. Service aktivieren und starten
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
    sudo journalctl -u scan-web -n 30 --no-pager
    echo ""
    echo -e "${YELLOW}Tipp: Prüfe die Logs mit: sudo journalctl -u scan-web -f${NC}"
    exit 1
fi

# 12. Netzwerk-Informationen
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
if [[ -n "$HOSTNAME" ]]; then
    echo -e "   ${GREEN}Hostname:${NC}     http://$HOSTNAME.local:$SERVICE_PORT"
fi
echo ""
echo "💡 PWA Installation (nur über HTTPS):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   Für PWA-Installation über HTTPS nutze einen Tunnel:"
echo ""
echo "   # Option 1: Cloudflare Tunnel (kostenlos)"
echo "   sudo snap install cloudflared"
echo "   cloudflared tunnel --url http://localhost:$SERVICE_PORT"
echo ""
echo "   # Option 2: ngrok"
echo "   curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null"
echo "   echo 'deb https://ngrok-agent.s3.amazonaws.com buster main' | sudo tee /etc/apt/sources.list.d/ngrok.list"
echo "   sudo apt update && sudo apt install ngrok"
echo "   ngrok http $SERVICE_PORT"
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
echo "🔧 Erste Schritte:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   1. Öffne http://localhost:$SERVICE_PORT im Browser"
echo "   2. Drücke F12 für Developer Console"
echo "   3. Prüfe ob Scans angezeigt werden"
echo ""
echo "   Falls Scans nicht angezeigt werden:"
echo "   - Prüfe Browser-Console auf Fehler (F12)"
echo "   - Teste die API: curl http://localhost:$SERVICE_PORT/api/scans"
echo ""
echo -e "${GREEN}Viel Erfolg mit deinem Scanner! 🖨️${NC}"
echo ""