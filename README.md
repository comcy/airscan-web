# 🖨️ AirScan Web - Scanner Web Interface

PWA-basiertes Webinterface für HP AirScan-kompatible Drucker/Scanner.

## ✨ Features

- 📱 **PWA** - Installierbar als native App auf allen Geräten
- 🎨 **Modern** - Responsive Design, optimiert für Mobile & Desktop
- ⚡ **Schnell** - Service Worker für Offline-Funktionalität
- 🔄 **Live** - Scan-Status und Download-Liste in Echtzeit
- 🗜️ **Komprimierung** - Automatische PDF-Komprimierung
- 📝 **OCR** - Optionale Texterkennung (Deutsch/Englisch)
- 🌐 **Netzwerk** - Zugriff von jedem Gerät im Netzwerk

## 📋 Voraussetzungen

- Ubuntu/Debian Linux
- Python 3.8+
- HP AirScan-kompatibler Scanner
- `hp-scan` Tool (HPLIP)

## 🚀 Installation

### 1. Repository klonen
```bash
git clone https://github.com/comcy/airscan-web.git
cd airscan-web
```

### 2. Installation ausführen
```bash
chmod +x setup.sh
./setup.sh
```

Das Setup-Skript:
- ✅ Installiert alle System-Abhängigkeiten
- ✅ Erstellt Python Virtual Environment
- ✅ Kopiert alle Dateien
- ✅ Generiert PWA-Icons
- ✅ Richtet Systemd-Service ein
- ✅ Startet die App automatisch

### 3. App öffnen

Nach erfolgreicher Installation ist die App erreichbar unter:

- **Lokal**: http://localhost:5000
- **Netzwerk**: http://\<deine-ip\>:5000

## 📱 Als PWA installieren

1. Öffne die App im Browser (Chrome/Safari/Edge)
2. Klicke auf **"Installieren"** im grünen Banner
3. Die App wird zum Homescreen hinzugefügt

## ⚙️ Konfiguration

### Scanner-Device anpassen

Bearbeite `~/airscan.sh` und passe die Zeile mit `DEVICE_URI` an:
```bash
DEVICE_URI="airscan:e0:HP OfficeJet Pro 8120e series [A662F3]"
```

Verfügbare Geräte anzeigen:
```bash
hp-scan -g
```

### Port ändern

Bearbeite `/etc/systemd/system/scan-web.service` und ändere:
```ini
ExecStart=.../uvicorn app:app --host 0.0.0.0 --port 5000
```

Dann Service neu starten:
```bash
sudo systemctl daemon-reload
sudo systemctl restart scan-web
```

## 🔧 Verwaltung
```bash
# Status anzeigen
sudo systemctl status scan-web

# Service neustarten
sudo systemctl restart scan-web

# Logs anschauen
sudo journalctl -u scan-web -f

# Service stoppen
sudo systemctl stop scan-web

# Service deaktivieren
sudo systemctl disable scan-web
```

## 📂 Verzeichnisstruktur
```
~/scan-web/          # App-Installation
~/airscan.sh         # Scan-Skript
~/scans/             # Gescannte PDFs
~/scans/.airscan/    # Temporäre Dateien
```

## 🛠️ Entwicklung

### Lokalen Dev-Server starten
```bash
cd src
python3 -m venv venv
source venv/bin/activate
pip install -r ../requirements.txt
uvicorn app:app --reload --port 5000
```

### Icons neu generieren
```bash
cd src
python3 generate-icons.py
```

## 📸 Screenshots

_(Hier könntest du Screenshots einfügen)_

## 🤝 Beitragen

Contributions sind willkommen! Bitte erstelle einen Pull Request.

## 📄 Lizenz

MIT License - siehe [LICENSE](LICENSE) Datei.

## 🙏 Credits

- FastAPI - https://fastapi.tiangolo.com/
- HPLIP - https://developers.hp.com/hp-linux-imaging-and-printing

## ⚠️ Bekannte Probleme

- OCR benötigt `tesseract-ocr-deu` Package
- ADF-Modus erstellt manchmal doppelte Seiten bei manchen Scannern

## 💡 Tipps

- Für beste Qualität: 300 DPI für Dokumente, 600 DPI für Fotos
- OCR funktioniert am besten mit Graustufen-Scans
- Komprimierung reduziert Dateigröße um ~70%

---

Made with ❤️ for easy scanning