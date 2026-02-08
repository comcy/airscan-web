#!/usr/bin/env bash
set -euo pipefail

SCAN_START=$(date +%s)
DEVICE_URI="airscan:e0:HP OfficeJet Pro 8120e series [A662F3]"

# Wo die fertigen PDFs landen
BASE_DIR="$HOME/scans"
# Temporäre Dateien
TMP_DIR="$BASE_DIR/.airscan"

RESOLUTION=150
MODE="color"
SOURCE="adf"
NAME="scan"
COMPRESS=true
OCR=false

# Cleanup-Funktion
cleanup() {
  if [[ -d "$TMP_DIR" ]]; then
    cd "$TMP_DIR"
    rm -f hpscan*.pdf hpscan_pg*_*.png scan.err 2>/dev/null || true
  fi
}
trap cleanup EXIT

# Parameter parsen
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--name) NAME="$2"; shift 2 ;;
    -r|--resolution) RESOLUTION="$2"; shift 2 ;;
    -m|--mode) MODE="$2"; shift 2 ;;
    --flatbed) SOURCE="flatbed"; shift ;;
    --adf) SOURCE="adf"; shift ;;
    --no-compress) COMPRESS=false; shift ;;
    --ocr) OCR=true; shift ;;
    -h|--help) 
      cat << EOF
Usage: airscan.sh [OPTIONS]

Optionen:
  -n, --name NAME         Name der Scan-Datei (Standard: scan)
  -r, --resolution DPI    Auflösung in DPI (Standard: 150)
  -m, --mode MODE         Modus: color, gray, lineart (Standard: color)
  --adf                   Automatischer Einzug (Standard)
  --flatbed               Flachbettscanner
  --no-compress           PDF nicht komprimieren
  --ocr                   OCR-Texterkennung durchführen
  -h, --help              Diese Hilfe anzeigen

Beispiele:
  airscan.sh -n rechnung --ocr
  airscan.sh -n foto --flatbed --no-compress -r 300
EOF
      exit 0 
      ;;
    *) echo "❌ Unbekannter Parameter: $1"; exit 1 ;;
  esac
done

# OCR-Abhängigkeit prüfen
if [[ "$OCR" == true ]] && ! command -v ocrmypdf &> /dev/null; then
  echo "❌ ocrmypdf ist nicht installiert!"
  echo "   Installation: sudo apt install ocrmypdf tesseract-ocr-deu"
  exit 1
fi

# Verzeichnisse sicherstellen
mkdir -p "$BASE_DIR" "$TMP_DIR"
cd "$TMP_DIR"

# Alte temporäre Dateien aufräumen (älter als 1 Tag)
find "$TMP_DIR" -type f \( -name "*.png" -o -name "*.pdf" \) -mtime +1 -delete 2>/dev/null || true

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
OUT_NAME="${NAME}_${TIMESTAMP}"
TMP_PDF="$TMP_DIR/temp_scan.pdf"
FINAL_PDF="$BASE_DIR/$OUT_NAME.pdf"

# Scan-Befehl zusammenstellen
SCAN_CMD=(hp-scan --device "$DEVICE_URI" --resolution "$RESOLUTION" --mode "$MODE" --file "temp_scan")
[[ "$SOURCE" == "adf" ]] && SCAN_CMD+=(--adf) || SCAN_CMD+=(--flatbed)

echo "➡️  Device: $DEVICE_URI"
echo "➡️  Quelle: $SOURCE"
echo "➡️  Auflösung: $RESOLUTION dpi"
echo "➡️  Modus: $MODE"
[[ "$COMPRESS" == true ]] && echo "➡️  Komprimierung: aktiviert"
[[ "$OCR" == true ]] && echo "➡️  OCR: aktiviert"
echo "➡️  Ziel-PDF: $FINAL_PDF"
echo "➡️  Starte Scan…"

# Scan durchführen
set +e
"${SCAN_CMD[@]}" 2>scan.err
SCAN_EXIT=$?
set -e

if grep -q "Error during device I/O" scan.err; then
  echo "ℹ️  ADF-Ende erkannt (harmlos)"
elif [[ $SCAN_EXIT -ne 0 ]]; then
  echo "❌ Scan fehlgeschlagen:"
  cat scan.err
  exit 1
fi

rm -f scan.err

# Prüfen, was der Scanner erstellt hat
shopt -s nullglob
pdf_files=(hpscan*.pdf)
png_files=(hpscan_pg*_*.png)

if (( ${#pdf_files[@]} > 0 )); then
  # Scanner hat direkt PDF erstellt (ADF-Modus)
  echo "ℹ️  Scanner hat PDF erstellt: ${pdf_files[0]}"
  mv "${pdf_files[0]}" "$TMP_PDF"
elif (( ${#png_files[@]} > 0 )); then
  # Scanner hat PNGs erstellt (Flatbed-Modus)
  echo "ℹ️  ${#png_files[@]} Seite(n) als PNG gescannt"
  echo "➡️  Erzeuge PDF…"
  magick "${png_files[@]}" -density "$RESOLUTION" "$TMP_PDF"
  rm -f "${png_files[@]}"
else
  echo "❌ Keine Scanseiten gefunden!"
  exit 1
fi

# OCR durchführen (falls gewünscht)
if [[ "$OCR" == true ]]; then
  echo "➡️  Führe OCR durch…"
  OCR_PDF="$TMP_DIR/temp_ocr.pdf"
  if ocrmypdf -l deu --rotate-pages --deskew --clean "$TMP_PDF" "$OCR_PDF" 2>/dev/null; then
    mv "$OCR_PDF" "$TMP_PDF"
    echo "✅ OCR abgeschlossen"
  else
    echo "⚠️  OCR fehlgeschlagen, verwende Original-PDF"
  fi
fi

# PDF komprimieren (falls gewünscht)
if [[ "$COMPRESS" == true ]]; then
  echo "➡️  Komprimiere PDF…"
  COMPRESSED_PDF="$TMP_DIR/temp_compressed.pdf"
  
  if gs -sDEVICE=pdfwrite \
        -dCompatibilityLevel=1.4 \
        -dPDFSETTINGS=/ebook \
        -dNOPAUSE -dQUIET -dBATCH \
        -sOutputFile="$COMPRESSED_PDF" \
        "$TMP_PDF" 2>/dev/null; then
    
    ORIGINAL_SIZE=$(stat -c%s "$TMP_PDF")
    COMPRESSED_SIZE=$(stat -c%s "$COMPRESSED_PDF")
    REDUCTION=$(( 100 - (COMPRESSED_SIZE * 100 / ORIGINAL_SIZE) ))
    
    mv "$COMPRESSED_PDF" "$TMP_PDF"
    echo "✅ Komprimierung: -${REDUCTION}% ($(numfmt --to=iec-i --suffix=B $ORIGINAL_SIZE) → $(numfmt --to=iec-i --suffix=B $COMPRESSED_SIZE))"
  else
    echo "⚠️  Komprimierung fehlgeschlagen, verwende Original-PDF"
  fi
fi

# Finale PDF verschieben
mv "$TMP_PDF" "$FINAL_PDF"

# Scandauer berechnen
SCAN_END=$(date +%s)
DURATION=$((SCAN_END - SCAN_START))

echo "✅ Fertig: $FINAL_PDF"
echo "⏱️  Dauer: ${DURATION}s"