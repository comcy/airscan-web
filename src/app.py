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

app = FastAPI(title="Scanner API", version="1.0")

SCAN_SCRIPT = "/home/cy/airscan.sh"
SCANS_DIR = "/home/cy/scans"

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
    html_path = os.path.join(os.path.dirname(__file__), "index.html")
    with open(html_path, "r", encoding="utf-8") as f:
        return f.read()

@app.post("/api/scan", response_model=ScanResponse)
async def start_scan(request: ScanRequest):
    """Start a scan job"""
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
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=300
        )
        
        # Find latest PDF
        pdf_files = glob.glob(f"{SCANS_DIR}/*.pdf")
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
        pdf_files = glob.glob(f"{SCANS_DIR}/*.pdf")
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

@app.get("/manifest.json")
async def manifest():
    """Serve PWA manifest"""
    manifest_path = os.path.join(os.path.dirname(__file__), "manifest.json")
    return FileResponse(manifest_path, media_type="application/json")

@app.get("/service-worker.js")
async def service_worker():
    """Serve service worker"""
    sw_path = os.path.join(os.path.dirname(__file__), "service-worker.js")
    return FileResponse(sw_path, media_type="application/javascript")

@app.get("/icon-{size}.png")
async def icon(size: int):
    """Serve PWA icons"""
    icon_path = os.path.join(os.path.dirname(__file__), f"icon-{size}.png")
    if os.path.exists(icon_path):
        return FileResponse(icon_path, media_type="image/png")
    raise HTTPException(status_code=404, detail="Icon not found")

@app.get("/favicon.ico")
async def favicon():
    """Serve favicon"""
    favicon_path = os.path.join(os.path.dirname(__file__), "favicon.ico")
    if os.path.exists(favicon_path):
        return FileResponse(favicon_path, media_type="image/x-icon")
    raise HTTPException(status_code=404, detail="Favicon not found")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=5000)
