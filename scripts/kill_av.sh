#!/bin/bash
# kill_av.sh — Instantly disable webcam and all microphone inputs

# Unload webcam kernel module
if modprobe -r uvcvideo 2>/dev/null; then
    echo "Webcam:    OFF (kernel module unloaded)"
else
    echo "Webcam:    already off"
fi

# Mute at ALSA level
amixer -q set Capture nocap 2>/dev/null && echo "ALSA mic:  MUTED"

# Mute at PulseAudio level
pactl set-source-mute @DEFAULT_SOURCE@ 1 2>/dev/null && echo "PulseAudio: MUTED"

# Mute at PipeWire level (if using PipeWire instead of PulseAudio)
wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 1 2>/dev/null && echo "PipeWire:  MUTED"

echo "All audio/video inputs disabled."
echo "To re-enable webcam: sudo modprobe uvcvideo"
echo "To unmute mic:       pactl set-source-mute @DEFAULT_SOURCE@ 0"
