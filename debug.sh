#!/usr/bin/env bash

echo "🔍 AirScan Web - Diagnose"
echo "=========================="
echo ""

# Service Status
echo "📊 Service Status:"
sudo systemctl status scan-web --no-pager | head -n 10
echo ""

# Ports
echo "🔌 Offene Ports:"
sudo netstat -tlnp | grep :5000 || echo "   Port 5000 nicht offen!"
echo ""

# Verzeichnisse
echo "📁 Verzeichnisse:"
echo "   Install-Dir: $(ls -la ~/scan-web 2>/dev/null | wc -l) Dateien"
echo "   Scans-Dir:   $(ls -la ~/scans/*.pdf 2>/dev/null | wc -l) PDFs"
echo ""
if [ -d ~/scans ]; then
    echo "   Scans-Verzeichnis Inhalt:"
    ls -lh ~/scans/*.pdf 2>/dev/null || echo "      Keine PDFs gefunden"
fi
echo ""

# Python-Umgebung
echo "🐍 Python:"
source ~/scan-web/venv/bin/activate 2>/dev/null && python --version && deactivate
echo ""

# API-Test
echo "🌐 API-Test:"
echo "   Homepage:"
curl -s -o /dev/null -w "      Status: %{http_code}\n" http://localhost:5000/ || echo "      Nicht erreichbar!"
echo "   Scans-API:"
curl -s http://localhost:5000/api/scans | jq '.' 2>/dev/null || echo "      API-Fehler"
echo ""

# Logs
echo "📝 Letzte Service-Logs:"
sudo journalctl -u scan-web -n 20 --no-pager
echo ""

echo "✅ Diagnose abgeschlossen"