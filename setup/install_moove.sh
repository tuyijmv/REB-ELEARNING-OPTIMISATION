#!/bin/bash
set -e

MOODLE_DIR="/var/www/html/moodle_app"
THEME_NAME="moove"
THEME_REPO="https://github.com/willianmano/moodle-theme_moove.git"
THEME_ZIP_URL="https://github.com/willianmano/moodle-theme_moove/archive/refs/heads/main.zip"

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
    echo "[INFO] Moove theme not found. Downloading from $THEME_REPO ..."
    mkdir -p "$MOODLE_DIR/theme"
    if curl -fsSL "$THEME_ZIP_URL" -o /tmp/moove.zip && \
       unzip -q /tmp/moove.zip -d /tmp && \
       mv /tmp/moodle-theme_moove-main "$THEME_DEST"; then
        echo "[OK] Moove theme downloaded and extracted to $THEME_DEST"
        rm -f /tmp/moove.zip
        rm -rf /tmp/moodle-theme_moove-main
    else
        echo "[ERROR] Failed to download or extract Moove theme."
        exit 1
    fi
fi

if [ -d "$THEME_DEST" ] && [ ! -d "$THEME_PUBLIC_DEST" ]; then
    echo "[INFO] Mirroring theme to public/theme for Moodle 5.1+ compatibility..."
    mkdir -p "$(dirname "$THEME_PUBLIC_DEST")"
    cp -a "$THEME_DEST" "$THEME_PUBLIC_DEST"
fi

echo "[INFO] Checking Moove theme version compatibility..."
MOODLE_VERSION=""
if [ -f "$MOODLE_DIR/public/version.php" ]; then
    MOODLE_VERSION=$(grep -oP '(?<=\$version\s*=\s*")[0-9]+' "$MOODLE_DIR/public/version.php" || true)
elif [ -f "$MOODLE_DIR/version.php" ]; then
    MOODLE_VERSION=$(grep -oP '(?<=\$version\s*=\s*")[0-9]+' "$MOODLE_DIR/version.php" || true)
fi

if [ -n "$MOODLE_VERSION" ]; then
    echo "[INFO] Installed Moodle version: $MOODLE_VERSION"

    for theme_path in "$THEME_PUBLIC_DEST" "$THEME_DEST"; do
        if [ -f "$theme_path/version.php" ]; then
            echo "[INFO] Patching $theme_path/version.php for compatibility..."
            sed -i "s/\$plugin->requires = [0-9]*;/\$plugin->requires = $MOODLE_VERSION;/" "$theme_path/version.php" || true
            echo "[OK] Patched $theme_path/version.php"
        fi
    done
else
    echo "[WARN] Could not detect Moodle version. Skipping compatibility patch."
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
