#!/usr/bin/env python3
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, HTMLResponse
from pydantic import BaseModel
import subprocess
import os
import glob
from datetime import datetime
from typing import Optional
from pathlib import Path

app = FastAPI(title="Scanner API", version="1.0")

# WICHTIG: Pfade absolut machen
SCAN_SCRIPT = os.path.expanduser("~/airscan.sh")
SCANS_DIR = os.path.expanduser("~/scans")
APP_DIR = Path(__file__).parent.absolute()

# Debug-Logging
print(f"📂 SCANS_DIR: {SCANS_DIR}")
print(f"📂 APP_DIR: {APP_DIR}")
print(f"📄 SCAN_SCRIPT: {SCAN_SCRIPT}")

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
    
    print(f"📋 Command: {' '.join(cmd)}")
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        print(f"✅ Scan completed with exit code: {result.returncode}")
        
        # Find latest PDF
        pdf_pattern = os.path.join(SCANS_DIR, "*.pdf")
        pdf_files = glob.glob(pdf_pattern)
        print(f"📂 Found {len(pdf_files)} PDFs in {SCANS_DIR}")
        
        if pdf_files:
            latest_pdf = max(pdf_files, key=os.path.getctime)
            filename = os.path.basename(latest_pdf)
            print(f"📄 Latest PDF: {filename}")
            
            return ScanResponse(
                success=True,
                output=result.stdout,
                filename=filename,
                downloadUrl=f"/api/download/{filename}"
            )
        else:
            print(f"❌ No PDFs found in {SCANS_DIR}")
            return ScanResponse(
                success=False,
                error="Keine PDF erstellt",
                output=result.stdout + "\n" + result.stderr
            )
            
    except subprocess.TimeoutExpired:
        print("❌ Scan timeout")
        raise HTTPException(status_code=500, detail="Scan-Timeout")
    except Exception as e:
        print(f"❌ Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/scans", response_model=list[ScanFile])
async def list_scans():
    """List all scanned PDFs"""
    try:
        pdf_pattern = os.path.join(SCANS_DIR, "*.pdf")
        pdf_files = glob.glob(pdf_pattern)
        
        print(f"📂 Listing scans from: {SCANS_DIR}")
        print(f"📋 Pattern: {pdf_pattern}")
        print(f"📄 Found {len(pdf_files)} files")
        
        scans = []
        
        for pdf in sorted(pdf_files, key=os.path.getctime, reverse=True)[:50]:
            try:
                stat = os.stat(pdf)
                filename = os.path.basename(pdf)
                print(f"   ✓ {filename} ({stat.st_size} bytes)")
                
                scans.append(ScanFile(
                    filename=filename,
                    size=stat.st_size,
                    created=datetime.fromtimestamp(stat.st_ctime).strftime('%Y-%m-%d %H:%M:%S'),
                    downloadUrl=f"/api/download/{filename}"
                ))
            except Exception as e:
                print(f"   ✗ Error processing {pdf}: {e}")
                continue
        
        print(f"✅ Returning {len(scans)} scans")
        return scans
        
    except Exception as e:
        print(f"❌ Error listing scans: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/download/{filename}")
async def download_file(filename: str):
    """Download a scanned PDF"""
    filepath = os.path.join(SCANS_DIR, filename)
    
    print(f"📥 Download request: {filename}")
    print(f"📂 Full path: {filepath}")
    
    # Security check
    if not os.path.abspath(filepath).startswith(os.path.abspath(SCANS_DIR)):
        print(f"❌ Security: Access denied")
        raise HTTPException(status_code=403, detail="Access denied")
    
    if not os.path.exists(filepath):
        print(f"❌ File not found")
        raise HTTPException(status_code=404, detail="File not found")
    
    print(f"✅ Sending file")
    return FileResponse(filepath, filename=filename, media_type="application/pdf")

@app.delete("/api/delete/{filename}")
async def delete_file(filename: str):
    """Delete a scanned PDF"""
    filepath = os.path.join(SCANS_DIR, filename)
    
    print(f"🗑️ Delete request: {filename}")
    
    # Security check
    if not os.path.abspath(filepath).startswith(os.path.abspath(SCANS_DIR)):
        raise HTTPException(status_code=403, detail="Access denied")
    
    try:
        if os.path.exists(filepath):
            os.remove(filepath)
            print(f"✅ Deleted: {filename}")
            return {"success": True}
        else:
            raise HTTPException(status_code=404, detail="File not found")
    except Exception as e:
        print(f"❌ Error deleting: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# PWA-Dateien servieren
@app.get("/manifest.json")
async def manifest():
    """Serve PWA manifest"""
    manifest_path = APP_DIR / "manifest.json"
    if not manifest_path.exists():
        raise HTTPException(status_code=404, detail="Manifest not found")
    return FileResponse(manifest_path, media_type="application/json")

@app.get("/service-worker.js")
async def service_worker():
    """Serve service worker"""
    sw_path = APP_DIR / "service-worker.js"
    if not sw_path.exists():
        raise HTTPException(status_code=404, detail="Service worker not found")
    return FileResponse(sw_path, media_type="application/javascript")

@app.get("/icon-{size}.png")
async def icon(size: int):
    """Serve PWA icons"""
    icon_path = APP_DIR / f"icon-{size}.png"
    if icon_path.exists():
        return FileResponse(icon_path, media_type="image/png")
    raise HTTPException(status_code=404, detail="Icon not found")

@app.get("/favicon.ico")
async def favicon():
    """Serve favicon"""
    favicon_path = APP_DIR / "favicon.ico"
    if favicon_path.exists():
        return FileResponse(favicon_path, media_type="image/x-icon")
    # Return a default 1x1 transparent favicon
    raise HTTPException(status_code=404, detail="Favicon not found")

if __name__ == "__main__":
    import uvicorn
    print("🚀 Starting Scanner Web Interface...")
    print(f"📂 Serving from: {APP_DIR}")
    print(f"📂 Scans directory: {SCANS_DIR}")
    uvicorn.run(app, host="0.0.0.0", port=5000)