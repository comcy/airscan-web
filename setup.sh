#!/usr/bin/env bash
set -euo pipefail

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Banner
echo -e "${BLUE}"
cat << "BANNER"
 █████  ██ ██████  ███████  ██████  █████  ███    ██       ██     ██ ███████ ██████  
██   ██ ██ ██   ██ ██      ██      ██   ██ ████   ██       ██     ██ ██      ██   ██ 
███████ ██ ██████  ███████ ██      ███████ ██ ██  ██ █████ ██  █  ██ █████   ██████  
██   ██ ██ ██   ██      ██ ██      ██   ██ ██  ██ ██       ██ ███ ██ ██      ██   ██ 
██   ██ ██ ██   ██ ███████  ██████ ██   ██ ██   ████        ███ ███  ███████ ██████  
BANNER
echo -e "${NC}"

# Verzeichnis-Check
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -f "$SCRIPT_DIR/src/app.py" ]]; then
    echo -e "${RED}❌ Fehler: Bitte aus dem Repository-Verzeichnis ausführen.${NC}"
    exit 1
fi

echo -e "${BLUE}📋 System-Voraussetzungen (Prerequisites):${NC}"
echo "-------------------------------------------------------"
echo "Das Programm benötigt folgende System-Komponenten:"
echo -e "1. ${YELLOW}sane-utils${NC}      (Für die Kommunikation mit AirScan-Geräten)"
echo -e "2. ${YELLOW}hplip${NC}           (Für HP-spezifische Funktionen/hp-scan)"
echo -e "3. ${YELLOW}imagemagick${NC}     (Für die Konvertierung von Scans in PDF)"
echo -e "4. ${YELLOW}ghostscript${NC}     (Für die Komprimierung der PDF-Dateien)"
echo -e "5. ${YELLOW}python3-venv${NC}    (Für die isolierte Python-Umgebung)"
echo -e "6. ${YELLOW}ocrmypdf${NC}        (Optional: Für die Texterkennung/OCR)"
echo "-------------------------------------------------------"
echo ""

# Bestätigung
read -p "Soll die Installation (inkl. Paket-Prüfung) gestartet werden? [J/n] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[JjYy]$ ]] && [[ ! -z $REPLY ]]; then
    echo "Abgebrochen."
    exit 0
fi

# 1. System-Abhängigkeiten prüfen und installieren
echo ""
echo "📦 Prüfe System-Pakete..."
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
    echo -e "${GREEN}✅ Alle System-Pakete vorhanden.${NC}"
fi

# 2. Installations-Pfade vorbereiten
HOME_DIR="$HOME"
INSTALL_DIR="$HOME_DIR/scan-web"
mkdir -p "$INSTALL_DIR"
mkdir -p "$HOME_DIR/scans"

# 3. Dateien kopieren
echo "📋 Kopiere App-Dateien..."
cp -r "$SCRIPT_DIR/src/"* "$INSTALL_DIR/"
# Kopiere das Skript in das App-Verzeichnis
mkdir -p "$INSTALL_DIR/scripts"
cp "$SCRIPT_DIR/scripts/airscan.sh" "$INSTALL_DIR/scripts/airscan.sh"
chmod +x "$INSTALL_DIR/scripts/airscan.sh"

# 4. .env Datei erstellen falls nicht vorhanden
if [[ ! -f "$INSTALL_DIR/.env" ]]; then
    echo "⚙️ Erstelle Standard .env Konfiguration..."
    echo 'DEVICE_URI=""' > "$INSTALL_DIR/.env"
fi

# 5. Python venv & Requirements
echo "🐍 Bereite Python Virtual Environment vor..."
cd "$INSTALL_DIR"
python3 -m venv venv
./venv/bin/pip install --upgrade pip -q
if [[ -f "$SCRIPT_DIR/requirements.txt" ]]; then
    ./venv/bin/pip install -r "$SCRIPT_DIR/requirements.txt" -q
else
    ./venv/bin/pip install fastapi uvicorn[standard] python-multipart pillow -q
fi

# 6. Systemd Service (Benutzer-Ebene)
echo "⚙️  Richte Systemd Service ein..."
mkdir -p "$HOME/.config/systemd/user"
cat << EOFSERVICE > "$HOME/.config/systemd/user/scan-web.service"
[Unit]
Description=Scanner Web Interface
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/venv/bin/python -m uvicorn app:app --host 0.0.0.0 --port 5000
Restart=always

[Install]
WantedBy=default.target
EOFSERVICE

systemctl --user daemon-reload
systemctl --user enable scan-web
systemctl --user restart scan-web

echo ""
echo -e "${GREEN}✨ Installation abgeschlossen! ✨${NC}"
echo "-------------------------------------------------------"
echo "Die App läuft nun im Hintergrund (Port 5000)."
echo "Konfiguration: $INSTALL_DIR/.env"
echo "Scans landen in: $HOME_DIR/scans/"
echo "-------------------------------------------------------"
