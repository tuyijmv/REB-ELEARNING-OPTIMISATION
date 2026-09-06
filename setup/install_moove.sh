#!/bin/bash
set -e

MOODLE_DIR="/var/www/html/moodle_app"
THEME_NAME="moove"
THEME_REPO="https://github.com/willianmano/moodle-theme_moove.git"

echo "=== Moove Theme Installer ==="
echo ""

if [ ! -f "$MOODLE_DIR/version.php" ] && [ ! -f "$MOODLE_DIR/public/version.php" ]; then
    echo "[ERROR] Moodle not found at $MOODLE_DIR"
    exit 1
fi

echo "[INFO] Detected Moodle directory: $MOODLE_DIR"

THEME_DEST="$MOODLE_DIR/theme/$THEME_NAME"
THEME_PUBLIC_DEST="$MOODLE_DIR/public/theme/$THEME_NAME"

if [ -d "$THEME_DEST" ] || [ -d "$THEME_PUBLIC_DEST" ]; then
    echo "[OK] Moove theme already present."
else
    echo "[INFO] Moove theme not found. Cloning from $THEME_REPO ..."
    mkdir -p "$MOODLE_DIR/theme"
    if git clone --depth 1 "$THEME_REPO" "$THEME_DEST"; then
        echo "[OK] Moove theme cloned to $THEME_DEST"
    else
        echo "[ERROR] Failed to clone Moove theme."
        exit 1
    fi
fi

if [ -d "$THEME_DEST" ] && [ ! -d "$THEME_PUBLIC_DEST" ]; then
    echo "[INFO] Mirroring theme to public/theme for Moodle 5.1+ compatibility..."
    mkdir -p "$(dirname "$THEME_PUBLIC_DEST")"
    cp -a "$THEME_DEST" "$THEME_PUBLIC_DEST"
fi

echo "[INFO] Running Moodle upgrade to register Moove theme..."
php "$MOODLE_DIR/admin/cli/upgrade.php" --non-interactive --allow-unstable || {
    echo "[WARN] upgrade.php reported issues (continuing)."
}

echo "[INFO] Setting Moove as the default theme..."
php "$MOODLE_DIR/admin/cli/cfg.php" --name=theme --set="$THEME_NAME"

echo "[INFO] Purging caches..."
php "$MOODLE_DIR/admin/cli/purge_caches.php"

echo ""
echo "[SUCCESS] Moove theme installed and set as default."
