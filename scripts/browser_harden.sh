#!/bin/bash
cd "$HOME" 2>/dev/null || cd /tmp
# browser_harden.sh — Apply arkenfox user.js to Firefox/LibreWolf
# + install uBlock Origin config
# Run as the desktop user (not root)

BROWSER=""
PROFILE_DIR=""

# Detect browser and profile
if command -v librewolf &>/dev/null; then
    BROWSER="librewolf"
    PROFILE_DIR=$(find ~/.librewolf -name "*.default*" -maxdepth 2 -type d 2>/dev/null | head -1)
elif command -v firefox &>/dev/null; then
    BROWSER="firefox"
    PROFILE_DIR=$(find ~/.mozilla/firefox -name "*.default*" -maxdepth 2 -type d 2>/dev/null | head -1)
fi

if [ -z "$PROFILE_DIR" ]; then
    echo "No Firefox/LibreWolf profile found. Launch the browser once to create a profile, then re-run."
    exit 1
fi

echo "Browser: $BROWSER"
echo "Profile: $PROFILE_DIR"
echo ""

# ── Download arkenfox user.js ────────────────────────────────────────────────
echo "→ Fetching arkenfox user.js..."
curl -fsSL "https://raw.githubusercontent.com/arkenfox/user.js/master/user.js" \
    -o "$PROFILE_DIR/user.js" || {
    echo "Download failed. Apply manually from https://github.com/arkenfox/user.js"
    exit 1
}

# ── Ghost Machine overrides (user-overrides.js) ──────────────────────────────
cat > "$PROFILE_DIR/user-overrides.js" << 'EOF'
// Ghost Machine — user-overrides.js
// These settings override arkenfox defaults for our use case

// Letterbox (resist fingerprinting via window size)
user_pref("privacy.resistFingerprinting", true);
user_pref("privacy.resistFingerprinting.letterboxing", true);

// Disable WebRTC completely (major leak vector)
user_pref("media.peerconnection.enabled", false);
user_pref("media.peerconnection.ice.no_host", true);

// Force DNS through proxy (critical for Tor)
user_pref("network.proxy.socks_remote_dns", true);

// Disable telemetry and studies hard
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("experiments.enabled", false);
user_pref("experiments.supported", false);
user_pref("app.shield.optoutstudies.enabled", false);

// Disable geolocation
user_pref("geo.enabled", false);
user_pref("geo.provider.network.url", "");

// Disable search suggestions (prevents keylogging your searches)
user_pref("browser.search.suggest.enabled", false);
user_pref("browser.urlbar.suggest.searches", false);
user_pref("browser.urlbar.speculativeConnect.enabled", false);

// No saved passwords, no autofill
user_pref("signon.rememberSignons", false);
user_pref("browser.formfill.enable", false);

// Clear on shutdown
user_pref("privacy.sanitize.sanitizeOnShutdown", true);
user_pref("privacy.clearOnShutdown.cache", true);
user_pref("privacy.clearOnShutdown.cookies", true);
user_pref("privacy.clearOnShutdown.downloads", true);
user_pref("privacy.clearOnShutdown.formdata", true);
user_pref("privacy.clearOnShutdown.history", true);
user_pref("privacy.clearOnShutdown.sessions", true);
user_pref("privacy.clearOnShutdown.siteSettings", false);
user_pref("privacy.clearOnShutdown.offlineApps", true);

// Disable prefetching (sends requests you didn't make)
user_pref("network.prefetch-next", false);
user_pref("network.dns.disablePrefetch", true);
user_pref("network.predictor.enabled", false);

// Spoof user agent to a common one (reduces uniqueness)
user_pref("general.useragent.override", "Mozilla/5.0 (Windows NT 10.0; rv:109.0) Gecko/20100101 Firefox/115.0");
EOF

echo "✅ user.js and user-overrides.js applied to $PROFILE_DIR"

# ── Auto-wipe profile script (run on browser close) ─────────────────────────
cat > "$HOME/.local/bin/browser_close_wipe.sh" << WIPEEOF
#!/bin/bash
# Wipe browser artifacts after session
sleep 2  # Wait for browser to fully close
find "$PROFILE_DIR" -name "*.sqlite" -exec sqlite3 {} \
    "DELETE FROM moz_historyvisits; DELETE FROM moz_inputhistory; DELETE FROM moz_cookies;" \; 2>/dev/null
find "$PROFILE_DIR/storage" -type f -delete 2>/dev/null
find "$PROFILE_DIR/cache2" -type f -delete 2>/dev/null
rm -rf "$PROFILE_DIR/.parentlock" 2>/dev/null
echo "Browser wipe complete."
WIPEEOF
chmod +x "$HOME/.local/bin/browser_close_wipe.sh"

echo "✅ Post-session browser wipe script created."
echo ""
echo "→ Manual steps:"
echo "   1. Install uBlock Origin from the browser's addon store"
echo "   2. In uBlock: enable 'I am an advanced user' → enable hard mode"
echo "   3. Add filter lists: uBlock filters, EasyList, EasyPrivacy, Malware domains"
echo "   4. Consider NoScript for JS per-site control"
echo "   5. Restart the browser for all settings to take effect"
