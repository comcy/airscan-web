#!/usr/bin/env python3
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
import subprocess
import os
import glob
from datetime import datetime
from typing import Optional
from pathlib import Path

app = FastAPI(title="Scanner API", version="1.0")

# Pfade
DEFAULT_SCAN_SCRIPT = os.path.expanduser("~/airscan.sh")
REPO_SCAN_SCRIPT = Path(__file__).parent.parent / "scripts" / "airscan.sh"

if os.path.exists(DEFAULT_SCAN_SCRIPT):
    SCAN_SCRIPT = DEFAULT_SCAN_SCRIPT
elif os.path.exists(REPO_SCAN_SCRIPT):
    SCAN_SCRIPT = str(REPO_SCAN_SCRIPT)
else:
    SCAN_SCRIPT = DEFAULT_SCAN_SCRIPT

# Lade Konfiguration aus .env Datei falls vorhanden
DEVICE_URI = None
env_path = Path(__file__).parent.parent / ".env"
if env_path.exists():
    with open(env_path, "r") as f:
        for line in f:
            if line.startswith("DEVICE_URI="):
                DEVICE_URI = line.split("=", 1)[1].strip().strip('"')

SCANS_DIR = os.path.expanduser("~/scans")
APP_DIR = Path(__file__).parent.absolute()

# ... restliche Klassen ...

@app.post("/api/scan", response_model=ScanResponse)
async def start_scan(request: ScanRequest):
    """Start a scan job"""
    if not os.path.exists(SCAN_SCRIPT):
        print(f"❌ Scan-Skript nicht gefunden: {SCAN_SCRIPT}")
        return ScanResponse(success=False, error=f"Scan-Skript nicht gefunden unter {SCAN_SCRIPT}")
    
    start_time = datetime.now().timestamp()
    
    cmd = [SCAN_SCRIPT, "-n", request.name, "-r", str(request.resolution), "-m", request.mode]
    
    # Füge DEVICE_URI hinzu falls in .env oder Umgebung gesetzt
    if DEVICE_URI:
        cmd.extend(["-d", DEVICE_URI])
    
    if request.source == "flatbed":
        cmd.append("--flatbed") 
    else:
        cmd.append("--adf")
    
    if not request.compress: cmd.append("--no-compress")
    if request.ocr: cmd.append("--ocr")
    
    print(f"🚀 Starte Scan mit Befehl: {' '.join(cmd)}")
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
        
        if result.returncode != 0:
            print(f"❌ Scan-Skript fehlgeschlagen (Code {result.returncode})")
            print(f"Stderr: {result.stderr}")
            return ScanResponse(
                success=False, 
                error=f"Scan-Skript fehlgeschlagen: {result.stderr.splitlines()[-1] if result.stderr else 'Unbekannter Fehler'}",
                output=result.stdout + "\n" + result.stderr
            )

        # Suche nach der neuesten PDF-Datei, die NACH dem Startzeitpunkt erstellt wurde
        pdf_files = glob.glob(os.path.join(SCANS_DIR, "*.pdf"))
        new_pdfs = [f for f in pdf_files if os.path.getctime(f) >= start_time - 1] # -1s Puffer
        
        if new_pdfs:
            latest_pdf = max(new_pdfs, key=os.path.getctime)
            filename = os.path.basename(latest_pdf)
            print(f"✅ Scan erfolgreich: {filename}")
            return ScanResponse(
                success=True,
                output=result.stdout,
                filename=filename,
                downloadUrl=f"/api/download/{filename}"
            )
        
        print("❌ Scan-Skript war erfolgreich, aber keine neue PDF-Datei gefunden.")
        return ScanResponse(success=False, error="Keine neue PDF erstellt (Script-Fehler?)", output=result.stdout)
    except subprocess.TimeoutExpired:
        print("❌ Scan-Timeout nach 10 Minuten")
        return ScanResponse(success=False, error="Timeout beim Scannen")
    except Exception as e:
        print(f"❌ Interner Fehler: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/download/{filename}")
async def download_file(filename: str):
    filepath = os.path.join(SCANS_DIR, filename)
    if not os.path.exists(filepath): raise HTTPException(status_code=404)
    return FileResponse(filepath, filename=filename, media_type="application/pdf")

@app.delete("/api/delete/{filename}")
async def delete_file(filename: str):
    filepath = os.path.join(SCANS_DIR, filename)
    if os.path.exists(filepath):
        os.remove(filepath)
        return {"success": True}
    raise HTTPException(status_code=404)

@app.get("/", response_class=HTMLResponse)
async def root():
    html_path = APP_DIR / "index.html"
    with open(html_path, "r", encoding="utf-8") as f:
        return f.read()

# Serve other static files
app.mount("/", StaticFiles(directory=str(APP_DIR), html=True), name="static")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=5000)
