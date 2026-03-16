#!/bin/bash
# hotkeys_debug.sh — diagnose why xbindkeys won't start
# Run as desktop user: bash hotkeys_debug.sh

echo "=== System info ==="
echo "USER: $USER"
echo "DISPLAY: $DISPLAY"
echo "XAUTHORITY: $XAUTHORITY"
echo ""

echo "=== xbindkeys installed? ==="
which xbindkeys && xbindkeys --version || echo "NOT FOUND"
echo ""

echo "=== xbindkeys verbose output ==="
xbindkeys --verbose --nodaemon &
XPID=$!
sleep 3
kill $XPID 2>/dev/null
echo ""

echo "=== Current ~/.xbindkeysrc ==="
cat ~/.xbindkeysrc 2>/dev/null || echo "File does not exist"
echo ""

echo "=== DISPLAY accessible? ==="
xdpyinfo > /dev/null 2>&1 && echo "DISPLAY OK" || echo "DISPLAY NOT ACCESSIBLE — this is the problem"
echo ""

echo "=== Running as? ==="
id
echo ""

echo "=== xfconf-query test ==="
xfconf-query -V 2>&1 | head -3
xfconf-query -c xfce4-keyboard-shortcuts -l 2>&1 | head -10
