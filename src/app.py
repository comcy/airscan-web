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

print(f"📂 APP_DIR: {APP_DIR}")
print(f"📂 SCANS_DIR: {SCANS_DIR}")

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
        # Check for HP scanner specifically as it is used in airscan.sh
        result = subprocess.run(["scanimage", "-L"], capture_output=True, text=True, timeout=5)
        if "HP" in result.stdout or "OfficeJet" in result.stdout:
            scanner_online = True
            # Try to extract name
            for line in result.stdout.splitlines():
                if "HP" in line or "OfficeJet" in line:
                    scanner_name = line.split("is a")[-1].strip() if "is a" in line else "HP Scanner"
                    break
    except Exception as e:
        print(f"⚠️ Error checking scanner status: {e}")

    return StatusResponse(
        service=True,
        scanner=scanner_online,
        scanner_name=scanner_name
    )

@app.get("/", response_class=HTMLResponse)
async def root():
    """Serve the web interface"""
    html_path = APP_DIR / "index.html"
    print(f"📄 Loading HTML from: {html_path}")
    
    if not html_path.exists():
        raise HTTPException(status_code=500, detail=f"index.html not found at {html_path}")
    
    with open(html_path, "r", encoding="utf-8") as f:
        return f.read()

@app.post("/api/scan", response_model=ScanResponse)
async def start_scan(request: ScanRequest):
    """Start a scan job"""
    print(f"🚀 Starting scan: {request.name}")
    
    if not os.path.exists(SCAN_SCRIPT):
        return ScanResponse(
            success=False,
            error=f"Scan-Skript nicht gefunden: {SCAN_SCRIPT}"
        )
    
    cmd = [SCAN_SCRIPT, "-n", request.name]
    cmd.extend(["-r", str(request.resolution)])
    cmd.extend(["-m", request.mode])
    
    if request.source == "flatbed":
        cmd.append("--flatbed")
    else:
        cmd.append("--adf")
    
    if not request.compress:
        cmd.append("--no-compress")
    
    if request.ocr:
        cmd.append("--ocr")
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        
        # Find latest PDF
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
        else:
            return ScanResponse(
                success=False,
                error="Keine PDF erstellt",
                output=result.stdout + "\n" + result.stderr
            )
            
    except subprocess.TimeoutExpired:
        raise HTTPException(status_code=500, detail="Scan-Timeout")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/scans", response_model=list[ScanFile])
async def list_scans():
    """List all scanned PDFs"""
    try:
        pdf_files = glob.glob(os.path.join(SCANS_DIR, "*.pdf"))
        scans = []
        
        for pdf in sorted(pdf_files, key=os.path.getctime, reverse=True)[:50]:
            stat = os.stat(pdf)
            scans.append(ScanFile(
                filename=os.path.basename(pdf),
                size=stat.st_size,
                created=datetime.fromtimestamp(stat.st_ctime).strftime('%Y-%m-%d %H:%M:%S'),
                downloadUrl=f"/api/download/{os.path.basename(pdf)}"
            ))
        
        return scans
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/download/{filename}")
async def download_file(filename: str):
    """Download a scanned PDF"""
    filepath = os.path.join(SCANS_DIR, filename)
    
    # Security check
    if not os.path.abspath(filepath).startswith(os.path.abspath(SCANS_DIR)):
        raise HTTPException(status_code=403, detail="Access denied")
    
    if not os.path.exists(filepath):
        raise HTTPException(status_code=404, detail="File not found")
    
    return FileResponse(filepath, filename=filename, media_type="application/pdf")

@app.delete("/api/delete/{filename}")
async def delete_file(filename: str):
    """Delete a scanned PDF"""
    filepath = os.path.join(SCANS_DIR, filename)
    
    # Security check
    if not os.path.abspath(filepath).startswith(os.path.abspath(SCANS_DIR)):
        raise HTTPException(status_code=403, detail="Access denied")
    
    try:
        if os.path.exists(filepath):
            os.remove(filepath)
            return {"success": True}
        else:
            raise HTTPException(status_code=404, detail="File not found")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# Serve index.html at root
@app.get("/")
async def read_root():
    """Serve main HTML file"""
    html_file = APP_DIR / "index.html"
    if not html_file.exists():
        raise HTTPException(status_code=404, detail="index.html not found")
    return FileResponse(html_file)

# Mount static files LAST (after all routes)
# This serves manifest.json, service-worker.js, icons, etc.
app.mount("/", StaticFiles(directory=str(APP_DIR), html=True), name="static")

if __name__ == "__main__":
    import uvicorn
    print("🚀 Starting Scanner Web Interface...")
    uvicorn.run(app, host="0.0.0.0", port=5000)