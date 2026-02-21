# 🖨️ AirScan Web - Scanner Web Interface

PWA-based web interface for HP AirScan-compatible printers/scanners.

## ✨ Features

- 📱 **PWA** - Installable as a native app on all devices
- 🎨 **Modern** - Responsive design, optimized for mobile & desktop
- ⚡ **Fast** - Service Worker for offline functionality
- 🔄 **Live** - Scan status and download list in real-time
- 🗜️ **Compression** - Automatic PDF compression
- 📝 **OCR** - Optional text recognition (German/English)
- 🌐 **Network** - Access from any device on the network

## 📋 Prerequisites

- Ubuntu/Debian Linux
- Python 3.8+
- HP AirScan-compatible scanner
- `hp-scan` Tool (HPLIP)

## 🚀 Installation

### One-Line Installation (One-Liner)

To install or update Airscan-Web, simply copy the following command into your terminal and execute it:

```bash
curl -sL https://raw.githubusercontent.com/comcy/airscan-web/main/install.sh | bash
```

The script will automatically clone the repository (if not already done), fetch the latest updates, and perform all necessary installation steps, including:
- ✅ Installation of all system dependencies
- ✅ Creation of a Python Virtual Environment
- ✅ Copying all application files
- ✅ Generation of PWA icons
- ✅ Setup of the Systemd service
- ✅ Automatic application startup

### Manual Installation (Optional)

If you prefer manual control over the process, you can follow these steps:

1.  **Clone Repository**
    ```bash
    git clone https://github.com/comcy/airscan-web.git
    cd airscan-web
    ```

2.  **Execute Installation**
    ```bash
    chmod +x setup.sh
    ./setup.sh
    ```

### 3. Open App

After successful installation, the app is accessible at:

-   **Local**: http://localhost:5000
-   **Network**: http://<your-ip>:5000

## 📱 Install as PWA

1.  Open the app in your browser (Chrome/Safari/Edge)
2.  Click on **"Install"** in the green banner
3.  The app will be added to your homescreen

## ⚙️ Configuration

### Adjust Scanner Device

Edit `~/airscan.sh` and adjust the line with `DEVICE_URI`:
```bash
DEVICE_URI="airscan:e0:HP OfficeJet Pro 8120e series [A662F3]"
```

Show available devices:
```bash
hp-scan -g
```

### Change Port

Edit `/etc/systemd/system/scan-web.service` and change:
```ini
ExecStart=.../uvicorn app:app --host 0.0.0.0 --port 5000
```

Then restart the service:
```bash
sudo systemctl daemon-reload
sudo systemctl restart scan-web
```

## 🔧 Management
```bash
# Show status
sudo systemctl status scan-web

# Restart service
sudo systemctl restart scan-web

# View logs
sudo journalctl -u scan-web -f

# Stop service
sudo systemctl stop scan-web

# Disable service
sudo systemctl disable scan-web
```

## 📂 Directory Structure
```
~/scan-web/          # App installation
~/airscan.sh         # Scan script
~/scans/             # Scanned PDFs
~/scans/.airscan/    # Temporary files
```

## 🛠️ Development

### Start Local Dev Server
```bash
cd src
python3 -m venv venv
source venv/bin/activate
pip install -r ../requirements.txt
uvicorn app:app --reload --port 5000
```

### Regenerate Icons
```bash
cd src
python3 generate-icons.py
```

## 📸 Screenshots

_(You could insert screenshots here)_

## 🤝 Contribute

Contributions are welcome! Please create a Pull Request.

## 📄 License

MIT License - see [LICENSE](LICENSE) file.

## 🙏 Credits

-   FastAPI - https://fastapi.tiangolo.com/
-   HPLIP - https://developers.hp.com/hp-linux-imaging-and-printing

## ⚠️ Known Issues

-   OCR requires `tesseract-ocr-deu` package
-   ADF mode sometimes creates duplicate pages with some scanners

## 💡 Tips

-   For best quality: 300 DPI for documents, 600 DPI for photos
-   OCR works best with grayscale scans
-   Compression reduces file size by ~70%

---

Made with ❤️ for easy scanning