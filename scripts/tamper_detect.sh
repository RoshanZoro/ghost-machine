#!/bin/bash
cd "$HOME" 2>/dev/null || cd /tmp
# tamper_detect.sh — Physical tamper detection using camera hash comparison
# On setup: photograph the glitter nail polish on screws/ports, store hash
# On boot: re-photograph and compare — alert if pattern changed
#
# Physical method: apply glitter nail polish over BIOS screws, port covers,
# and case seams. Each glitter pattern is unique and impossible to replicate.
# Photograph immediately after applying. Any tampering disturbs the pattern.

MODE="${1:-check}"
STORE_DIR="/var/lib/ghost/tamper"
LOG="/var/log/ghost/tamper.log"
CAMERA="/dev/video0"
mkdir -p "$STORE_DIR" /var/log/ghost

capture_image() {
    local OUTPUT="$1"
    # Use ffmpeg to grab a single frame
    if command -v ffmpeg &>/dev/null; then
        ffmpeg -f v4l2 -i "$CAMERA" -frames:v 1 -q:v 2 "$OUTPUT" -y 2>/dev/null
    elif command -v fswebcam &>/dev/null; then
        fswebcam -r 1280x720 --no-banner "$OUTPUT" 2>/dev/null
    else
        echo "No camera capture tool found. Install ffmpeg or fswebcam."
        return 1
    fi
}

hash_image() {
    local IMAGE="$1"
    sha256sum "$IMAGE" | awk '{print $1}'
}

setup_baseline() {
    echo "TAMPER DETECT SETUP"
    echo "━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Before running this:"
    echo "  1. Apply glitter nail polish over all BIOS screws"
    echo "  2. Apply over port covers, case seams"
    echo "  3. Photograph the laptop with good lighting"
    echo "  4. Let nail polish dry completely"
    echo ""
    echo "This script will now capture a reference image."
    echo "Place laptop in consistent position/lighting."
    read -rp "Press Enter when ready..."

    # Enable webcam module temporarily
    modprobe uvcvideo 2>/dev/null
    sleep 1

    BASELINE_IMG="$STORE_DIR/baseline_$(date +%Y%m%d_%H%M%S).jpg"
    if capture_image "$BASELINE_IMG"; then
        HASH=$(hash_image "$BASELINE_IMG")
        echo "$HASH  $BASELINE_IMG" > "$STORE_DIR/baseline.sha256"
        echo ""
        echo "✅ Baseline stored: $BASELINE_IMG"
        echo "   SHA256: $HASH"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Baseline set: $HASH" >> "$LOG"
    else
        echo "❌ Could not capture baseline image."
        echo "   Ensure webcam is connected and /dev/video0 exists."
    fi

    # Disable webcam again
    modprobe -r uvcvideo 2>/dev/null
}

run_check() {
    if [ ! -f "$STORE_DIR/baseline.sha256" ]; then
        echo "No baseline set. Run: $0 setup"
        exit 1
    fi

    BASELINE_HASH=$(awk '{print $1}' "$STORE_DIR/baseline.sha256")

    modprobe uvcvideo 2>/dev/null
    sleep 1

    CURRENT_IMG=$(mktemp /tmp/tamper_check_XXXXXX.jpg)
    if ! capture_image "$CURRENT_IMG"; then
        echo "⚠️  Could not capture check image."
        modprobe -r uvcvideo 2>/dev/null
        exit 1
    fi

    CURRENT_HASH=$(hash_image "$CURRENT_IMG")
    modprobe -r uvcvideo 2>/dev/null

    if [ "$CURRENT_HASH" = "$BASELINE_HASH" ]; then
        echo "✅ Tamper check: PASSED — no physical changes detected."
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Tamper check: PASSED" >> "$LOG"
        rm -f "$CURRENT_IMG"
    else
        echo "⚠️  TAMPER ALERT: Physical state has changed!"
        echo "   Baseline: $BASELINE_HASH"
        echo "   Current:  $CURRENT_HASH"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] TAMPER ALERT — hash mismatch" >> "$LOG"
        cp "$CURRENT_IMG" "$STORE_DIR/tamper_detected_$(date +%Y%m%d_%H%M%S).jpg"
        notify-send "⚠️ TAMPER ALERT" "Physical state changed. Device may have been accessed." 2>/dev/null || true
        wall "GHOST: TAMPER DETECTION ALERT — physical state changed. Check $LOG"
        rm -f "$CURRENT_IMG"
        exit 2
    fi
}

case "$MODE" in
    setup) setup_baseline ;;
    check) run_check ;;
    *)
        echo "Usage: $0 [setup|check]"
        echo "  setup — capture baseline glitter pattern (run after applying nail polish)"
        echo "  check — compare current state to baseline"
        exit 1
        ;;
esac
