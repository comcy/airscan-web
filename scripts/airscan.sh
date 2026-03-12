#!/usr/bin/env bash
set -euo pipefail

# 1. Lade Konfiguration aus .env falls vorhanden (im Repo-Root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/../.env" ]]; then
  export $(grep -v '^#' "$SCRIPT_DIR/../.env" | xargs)
fi

SCAN_START=$(date +%s)

# Standardwerte aus ENV oder Fallback
DEVICE_URI="${DEVICE_URI:-}"
BASE_DIR="$HOME/scans"
TMP_DIR="$BASE_DIR/.airscan"

RESOLUTION=150
MODE="color"
SOURCE="adf"
NAME="scan"
COMPRESS=true
OCR=false

# Parameter parsen
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--name) NAME="$2"; shift 2 ;;
    -r|--resolution) RESOLUTION="$2"; shift 2 ;;
    -m|--mode) MODE="$2"; shift 2 ;;
    -d|--device) DEVICE_URI="$2"; shift 2 ;;
    --flatbed) SOURCE="flatbed"; shift ;;
    --adf) SOURCE="adf"; shift ;;
    --no-compress) COMPRESS=false; shift ;;
    --ocr) OCR=true; shift ;;
    -h|--help) 
      echo "Usage: airscan.sh [OPTIONS]"
      exit 0 
      ;;
    *) echo "❌ Unbekannter Parameter: $1"; exit 1 ;;
  esac
done

# Automatische Erkennung falls immer noch leer
if [[ -z "$DEVICE_URI" ]]; then
  DEVICE_URI=$(scanimage -L | grep "hpaio" | head -n 1 | sed -n "s/device \`\(.*\)' is a .*/\1/p" || true)
  [[ -z "$DEVICE_URI" ]] && DEVICE_URI=$(scanimage -L | grep "airscan" | head -n 1 | sed -n "s/device \`\(.*\)' is a .*/\1/p" || true)
fi

echo "➡️  Device: $DEVICE_URI"

# Verzeichnisse sicherstellen
mkdir -p "$BASE_DIR" "$TMP_DIR"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
OUT_NAME="${NAME}_${TIMESTAMP}"
TMP_PDF="$TMP_DIR/temp_scan.pdf"
FINAL_PDF="$BASE_DIR/$OUT_NAME.pdf"

# --- MOCK MODUS ---
if [[ "$DEVICE_URI" == "mock" ]]; then
  echo "🧪 MOCK-MODE aktiviert. Erzeuge Test-Datei..."
  sleep 2
  # Erzeuge eine kleine valide PDF-Datei mittels ImageMagick oder einfach touch (für Minimal-Test)
  if command -v magick &> /dev/null; then
    magick -size 595x842 xc:white -pointsize 12 -draw "text 50,50 'MOCK SCAN $TIMESTAMP'" "$TMP_PDF"
  else
    touch "$TMP_PDF"
  fi
  mv "$TMP_PDF" "$FINAL_PDF"
  echo "✅ Mock-Scan fertig: $FINAL_PDF"
  exit 0
fi

# --- ECHTER SCAN ---
# (Rest der bisherigen Logik für hp-scan, OCR, GS...)
cd "$TMP_DIR"
SCAN_CMD=(hp-scan --device "$DEVICE_URI" --resolution "$RESOLUTION" --mode "$MODE" --file "temp_scan")
[[ "$SOURCE" == "adf" ]] && SCAN_CMD+=(--source=adf) || SCAN_CMD+=(--source=flatbed)

set +e
"${SCAN_CMD[@]}" 2>scan.err
SCAN_EXIT=$?
set -e

if [[ $SCAN_EXIT -ne 0 ]] && ! grep -q "Error during device I/O" scan.err; then
  cat scan.err >&2; exit 1
fi

shopt -s nullglob
pdf_files=(hpscan*.pdf); png_files=(hpscan_pg*_*.png)
if (( ${#pdf_files[@]} > 0 )); then
  mv "${pdf_files[0]}" "$TMP_PDF"
elif (( ${#png_files[@]} > 0 )); then
  magick "${png_files[@]}" -density "$RESOLUTION" "$TMP_PDF"
  rm -f "${png_files[@]}"
else
  echo "❌ Keine Scanseiten gefunden!" >&2; exit 1
fi

# PDF verschieben
mv "$TMP_PDF" "$FINAL_PDF"
echo "✅ Fertig: $FINAL_PDF"
