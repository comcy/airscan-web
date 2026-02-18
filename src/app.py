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
SCAN_SCRIPT = os.path.expanduser("~/airscan.sh")
SCANS_DIR = os.path.expanduser("~/scans")
APP_DIR = Path(__file__).parent.absolute()

# Stelle sicher, dass Verzeichnis existiert
os.makedirs(SCANS_DIR, exist_ok=True)

class ScanRequest(BaseModel):
    name: Optional[str] = "scan"
    resolution: int = 150
    mode: str = "color"
    source: str = "adf"
    compress: bool = True
    ocr: bool = False

class ScanResponse(BaseModel):
    success: bool
    output: Optional[str] = None
    filename: Optional[str] = None
    downloadUrl: Optional[str] = None
    error: Optional[str] = None

class ScanFile(BaseModel):
    filename: str
    size: int
    created: str
    downloadUrl: str

class StatusResponse(BaseModel):
    service: bool
    scanner: bool
    scanner_name: Optional[str] = None

@app.get("/api/status", response_model=StatusResponse)
async def get_status():
    """Check status of service and scanner"""
    scanner_online = False
    scanner_name = None
    
    try:
        # Check using scanimage -L
        result = subprocess.run(["scanimage", "-L"], capture_output=True, text=True, timeout=10)
        if any(keyword in result.stdout for keyword in ["HP", "OfficeJet", "airscan"]):
            scanner_online = True
            for line in result.stdout.splitlines():
                if "HP" in line or "OfficeJet" in line:
                    scanner_name = line.split("is a")[-1].strip() if "is a" in line else "Scanner"
                    break
    except Exception as e:
        print(f"⚠️ Status check error: {e}")

    return StatusResponse(
        service=True,
        scanner=scanner_online,
        scanner_name=scanner_name
    )

@app.get("/api/scans", response_model=list[ScanFile])
async def list_scans():
    """List all scanned PDFs"""
    try:
        pdf_files = glob.glob(os.path.join(SCANS_DIR, "*.pdf"))
        scans = []
        
        for pdf in sorted(pdf_files, key=os.path.getctime, reverse=True)[:50]:
            try:
                stat = os.stat(pdf)
                fname = os.path.basename(pdf)
                scans.append(ScanFile(
                    filename=fname,
                    size=stat.st_size,
                    created=datetime.fromtimestamp(stat.st_ctime).strftime('%Y-%m-%d %H:%M:%S'),
                    downloadUrl=f"/api/download/{fname}"
                ))
            except: continue
        
        return scans
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/scan", response_model=ScanResponse)
async def start_scan(request: ScanRequest):
    """Start a scan job"""
    if not os.path.exists(SCAN_SCRIPT):
        return ScanResponse(success=False, error="Scan-Skript nicht gefunden")
    
    cmd = [SCAN_SCRIPT, "-n", request.name, "-r", str(request.resolution), "-m", request.mode]
    
    # Matching the new airscan.sh parameters
    if request.source == "flatbed":
        cmd.append("--flatbed") 
    else:
        cmd.append("--adf")
    
    if not request.compress: cmd.append("--no-compress")
    if request.ocr: cmd.append("--ocr")
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        
        pdf_files = glob.glob(os.path.join(SCANS_DIR, "*.pdf"))
        if pdf_files:
            latest_pdf = max(pdf_files, key=os.path.getctime)
            filename = os.path.basename(latest_pdf)
            return ScanResponse(
                success=True,
                output=result.stdout,
                filename=filename,
                downloadUrl=f"/api/download/{filename}"
            )
        return ScanResponse(success=False, error="Keine PDF erstellt", output=result.stderr)
    except Exception as e:
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
