#!/bin/bash
cd "$HOME" 2>/dev/null || cd /tmp
# metadata_wipe.sh — Strip metadata from files before exfil or sharing
# Uses mat2 (primary) and exiftool (fallback)
# Usage: bash metadata_wipe.sh <file_or_directory>

TARGET="${1:-.}"  # Default to current directory

# Check dependencies
if ! command -v mat2 &>/dev/null && ! command -v exiftool &>/dev/null; then
    echo "Installing mat2 and exiftool..."
    pacman -S --needed --noconfirm perl-image-exiftool
    pip install mat2 --break-system-packages 2>/dev/null || \
        pacman -S --needed --noconfirm mat2
fi

LOG="/var/log/ghost/metadata_wipe.log"
mkdir -p /var/log/ghost

WIPED=0
FAILED=0

wipe_file() {
    local FILE="$1"
    local EXT="${FILE##*.}"
    local BASENAME
    BASENAME=$(basename "$FILE")

    # mat2 handles: pdf, odt, docx, jpg, png, mp3, mp4, zip, and more
    if command -v mat2 &>/dev/null; then
        if mat2 --inplace "$FILE" 2>/dev/null; then
            echo "  ✅ mat2:    $BASENAME"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] mat2 wiped: $FILE" >> "$LOG"
            (( WIPED++ ))
            return
        fi
    fi

    # exiftool fallback — strips all metadata in-place
    if command -v exiftool &>/dev/null; then
        if exiftool -all= -overwrite_original_in_place "$FILE" 2>/dev/null; then
            echo "  ✅ exiftool: $BASENAME"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] exiftool wiped: $FILE" >> "$LOG"
            (( WIPED++ ))
            return
        fi
    fi

    echo "  ⚠️  Skipped: $BASENAME (unsupported format or error)"
    (( FAILED++ ))
}

echo "Wiping metadata from: $TARGET"
echo ""

if [ -f "$TARGET" ]; then
    wipe_file "$TARGET"
elif [ -d "$TARGET" ]; then
    # Process all supported files recursively
    while IFS= read -r -d '' FILE; do
        wipe_file "$FILE"
    done < <(find "$TARGET" -type f \( \
        -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \
        -o -iname "*.gif" -o -iname "*.pdf" -o -iname "*.docx" \
        -o -iname "*.xlsx" -o -iname "*.pptx" -o -iname "*.odt" \
        -o -iname "*.mp3" -o -iname "*.mp4" -o -iname "*.mov" \
        -o -iname "*.zip" -o -iname "*.heic" -o -iname "*.tiff" \
    \) -print0)
else
    echo "Error: '$TARGET' is not a valid file or directory."
    exit 1
fi

echo ""
echo "Done. Wiped: $WIPED  |  Skipped: $FAILED"
