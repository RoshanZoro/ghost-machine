#!/bin/bash
# ghost_run.sh — clean environment wrapper for xterm hotkeys
# Usage: ghost_run.sh <script> [args]
# Silences the getcwd warning by resetting CWD before bash sees it
unset CDPATH
cd /tmp 2>&1 | grep -v "getcwd\|no such file" >&2 || true
exec sudo "$@"
