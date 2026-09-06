#!/bin/bash
set -e

MOODLE_DIR="/var/www/html/moodle_app"
THEME_NAME="moove"
THEME_REPO="https://github.com/willianmano/moodle-theme_moove.git"

echo "=== Moove Theme Installer ==="
echo ""

# Detect Moodle installation by checking both possible version.php locations
if [ ! -f "$MOODLE_DIR/version.php" ] && [ ! -f "$MOODLE_DIR/public/version.php" ]; then
    echo "[ERROR] Moodle not found at $MOODLE_DIR"
    exit 1
fi

echo "[INFO] Detected Moodle directory: $MOODLE_DIR"

# Theme destination paths
THEME_DEST="$MOODLE_DIR/theme/$THEME_NAME"
THEME_PUBLIC_DEST="$MOODLE_DIR/public/theme/$THEME_NAME"
UPGRADE_SCRIPT="$MOODLE_DIR/admin/cli/upgrade.php"
CFG_SCRIPT="$MOODLE_DIR/admin/cli/cfg.php"
PURGE_SCRIPT="$MOODLE_DIR/admin/cli/purge_caches.php"

# 1. Check if theme is already present in either location
if [ -d "$THEME_DEST" ] || [ -d "$THEME_PUBLIC_DEST" ]; then
    echo "[OK] Moove theme already present."
else
    echo "[INFO] Moove theme not found. Cloning from $THEME_REPO ..."
    mkdir -p "$MOODLE_DIR/theme"
    if git clone --depth 1 https://github.com/willianmano/moodle-theme_moove.git "$THEME_DEST"; then
        echo "[OK] Moove theme cloned to $THEME_DEST"
    else
        echo "[ERROR] Failed to clone Moove theme."
        exit 1
    fi
fi

# 2. Ensure theme is in a location Moodle 5.1+ can discover it.
# Moodle 5.1+ prefers themes under /public/theme/.
# If we only have it under /theme/, mirror it to /public/theme/.
if [ -d "$THEME_DEST" ] && [ ! -d "$THEME_PUBLIC_DEST" ]; then
    echo "[INFO] Mirroring theme to public/theme for Moodle 5.1+ compatibility..."
    mkdir -p "$(dirname "$THEME_PUBLIC_DEST")"
    cp -a "$THEME_DEST" "$THEME_PUBLIC_DEST"
fi

# 3. Run upgrade to register the theme in the database
echo "[INFO] Running Moodle upgrade to register Moove theme..."
php "$UPGRADE_SCRIPT" --non-interactive --allow-unstable || {
    echo "[WARN] upgrade.php reported issues (continuing)."
}

# 4. Set Moove as the default theme
echo "[INFO] Setting Moove as the default theme..."
php "$CFG_SCRIPT" --name=theme --set="$THEME_NAME"

# 5. Purge caches so the theme takes effect immediately
echo "[INFO] Purging caches..."
php "$PURGE_SCRIPT"

echo ""
echo "[SUCCESS] Moove theme installed and set as default."
