#!/usr/bin/env python3
from flask import Flask, render_template, request, jsonify, send_file
import subprocess
import os
import glob
from datetime import datetime
import json

app = Flask(__name__)

SCAN_SCRIPT = "/home/cy/airscan.sh"
SCANS_DIR = "/home/cy/scans"

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/scan', methods=['POST'])
def start_scan():
    """Startet den Scan-Prozess"""
    data = request.json
    
    # Parameter zusammenbauen
    cmd = [SCAN_SCRIPT]
    
    if data.get('name'):
        cmd.extend(['-n', data['name']])
    
    cmd.extend(['-r', str(data.get('resolution', 150))])
    cmd.extend(['-m', data.get('mode', 'color')])
    
    if data.get('source') == 'flatbed':
        cmd.append('--flatbed')
    else:
        cmd.append('--adf')
    
    if not data.get('compress', True):
        cmd.append('--no-compress')
    
    if data.get('ocr', False):
        cmd.append('--ocr')
    
    try:
        # Scan starten und Output sammeln
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=300  # 5 Minuten Timeout
        )
        
        # Suche die zuletzt erstellte PDF
        pdf_files = glob.glob(f"{SCANS_DIR}/*.pdf")
        if pdf_files:
            latest_pdf = max(pdf_files, key=os.path.getctime)
            filename = os.path.basename(latest_pdf)
            
            return jsonify({
                'success': True,
                'output': result.stdout,
                'filename': filename,
                'downloadUrl': f'/api/download/{filename}'
            })
        else:
            return jsonify({
                'success': False,
                'error': 'Keine PDF erstellt',
                'output': result.stdout + '\n' + result.stderr
            }), 500
            
    except subprocess.TimeoutExpired:
        return jsonify({
            'success': False,
            'error': 'Scan-Timeout (>5min)'
        }), 500
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/scans', methods=['GET'])
def list_scans():
    """Liste alle vorhandenen Scans"""
    try:
        pdf_files = glob.glob(f"{SCANS_DIR}/*.pdf")
        scans = []
        
        for pdf in sorted(pdf_files, key=os.path.getctime, reverse=True)[:20]:
            stat = os.stat(pdf)
            scans.append({
                'filename': os.path.basename(pdf),
                'size': stat.st_size,
                'created': datetime.fromtimestamp(stat.st_ctime).strftime('%Y-%m-%d %H:%M:%S'),
                'downloadUrl': f'/api/download/{os.path.basename(pdf)}'
            })
        
        return jsonify(scans)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/download/<filename>')
def download_file(filename):
    """Download einer gescannten PDF"""
    filepath = os.path.join(SCANS_DIR, filename)
    
    # Sicherheitscheck
    if not os.path.abspath(filepath).startswith(os.path.abspath(SCANS_DIR)):
        return "Access denied", 403
    
    if os.path.exists(filepath):
        return send_file(filepath, as_attachment=True)
    else:
        return "File not found", 404

@app.route('/api/delete/<filename>', methods=['DELETE'])
def delete_file(filename):
    """Löscht eine gescannte PDF"""
    filepath = os.path.join(SCANS_DIR, filename)
    
    # Sicherheitscheck
    if not os.path.abspath(filepath).startswith(os.path.abspath(SCANS_DIR)):
        return jsonify({'error': 'Access denied'}), 403
    
    try:
        if os.path.exists(filepath):
            os.remove(filepath)
            return jsonify({'success': True})
        else:
            return jsonify({'error': 'File not found'}), 404
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
