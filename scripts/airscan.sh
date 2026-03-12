#!/usr/bin/env bash
set -euo pipefail

# 1. Konfiguration laden
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$SCRIPT_DIR/../.env" ]] && export $(grep -v '^#' "$SCRIPT_DIR/../.env" | xargs)

# Pfade zu den Tools sicherstellen
MAGICK_CMD=$(command -v magick || command -v convert || echo "magick")
SCANIMAGE_CMD=$(command -v scanimage || echo "scanimage")

DEVICE_URI="${DEVICE_URI:-}"
BASE_DIR="$HOME/scans"
TMP_DIR="$BASE_DIR/.airscan"
mkdir -p "$BASE_DIR" "$TMP_DIR"

RESOLUTION=150
MODE="color"
SOURCE="adf"
NAME="scan"

# Parameter parsen
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--name) NAME="$2"; shift 2 ;;
    -r|--resolution) RESOLUTION="$2"; shift 2 ;;
    -m|--mode) MODE="$2"; shift 2 ;;
    -d|--device) DEVICE_URI="$2"; shift 2 ;;
    --flatbed) SOURCE="flatbed"; shift ;;
    --adf) SOURCE="adf"; shift ;;
    *) shift ;;
  esac
done

# Automatische Erkennung falls leer
if [[ -z "$DEVICE_URI" ]]; then
  DEVICE_URI=$($SCANIMAGE_CMD -L | grep -E "airscan|hpaio" | head -n 1 | sed -n "s/device \`\(.*\)' is a .*/\1/p" || true)
fi

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
FINAL_PDF="$BASE_DIR/${NAME}_${TIMESTAMP}.pdf"

echo "➡️  Device: $DEVICE_URI"
cd "$TMP_DIR"
rm -f scan_*.tiff hpscan*.pdf hpscan*.png 2>/dev/null || true

# --- STRATEGIE WÄHLEN ---
if [[ "$DEVICE_URI" == airscan:* ]]; then
  echo "🚀 Nutze AirScan (scanimage)..."
  
  SRC_PARAM="Flatbed"
  [[ "$SOURCE" == "adf" ]] && SRC_PARAM="ADF"
  
  set +e
  $SCANIMAGE_CMD -d "$DEVICE_URI" \
            --source "$SRC_PARAM" \
            --resolution "$RESOLUTION" \
            --mode "$MODE" \
            --format=tiff \
            --batch="scan_%d.tiff" 2>scan.err
  SCAN_EXIT=$?
  set -e
  
  if [[ $SCAN_EXIT -ne 0 ]]; then
    if ! ls scan_*.tiff &>/dev/null; then
      echo "❌ Scanimage Fehler:" >&2; cat scan.err >&2; exit 1
    fi
  fi

  echo "➡️  Konvertiere TIFF zu PDF..."
  $MAGICK_CMD scan_*.tiff "$FINAL_PDF"
  rm -f scan_*.tiff

elif [[ "$DEVICE_URI" == hpaio:* ]]; then
  echo "🚀 Nutze HPLIP (hp-scan)..."
  
  SCAN_CMD=(hp-scan --device="$DEVICE_URI" --res="$RESOLUTION" --mode="$MODE" --file="temp_scan")
  [[ "$SOURCE" == "adf" ]] && SCAN_CMD+=(--adf)
  
  set +e
  "${SCAN_CMD[@]}" 2>scan.err
  SCAN_EXIT=$?
  set -e
  
  shopt -s nullglob
  pdf_files=(hpscan*.pdf)
  if (( ${#pdf_files[@]} > 0 )); then
    mv "${pdf_files[0]}" "$FINAL_PDF"
  else
    png_files=(hpscan*.png)
    if (( ${#png_files[@]} > 0 )); then
      $MAGICK_CMD "${png_files[@]}" "$FINAL_PDF"
      rm "${png_files[@]}"
    else
      echo "❌ hp-scan Fehler:" >&2; cat scan.err >&2; exit 1
    fi
  fi
else
  echo "❌ Unbekannte Device-URI Strategie." >&2; exit 1
fi

echo "✅ Fertig: $FINAL_PDF"
