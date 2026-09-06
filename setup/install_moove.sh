#!/bin/bash
set -e

MOODLE_DIR="/var/www/html/moodle_app"
THEME_NAME="moove"
THEME_REPO="https://github.com/willianmano/moodle-theme_moove.git"
THEME_BRANCH="MOODLE_501_STABLE"
THEME_ZIP_URL="https://github.com/willianmano/moodle-theme_moove/archive/refs/heads/MOODLE_501_STABLE.zip"

echo "=== Moove Theme Installer ==="
echo ""

if [ ! -f "$MOODLE_DIR/version.php" ] && [ ! -f "$MOODLE_DIR/public/version.php" ]; then
    echo "[ERROR] Moodle not found at $MOODLE_DIR"
    exit 1
fi

echo "[INFO] Detected Moodle directory: $MOODLE_DIR"

THEME_DEST="$MOODLE_DIR/theme/$THEME_NAME"
THEME_PUBLIC_DEST="$MOODLE_DIR/public/theme/$THEME_NAME"
BOOTSTHEME_DEST="$MOODLE_DIR/theme/boost"
BOOTSTHEME_PUBLIC_DEST="$MOODLE_DIR/public/theme/boost"

if [ -d "$THEME_DEST" ] || [ -d "$THEME_PUBLIC_DEST" ]; then
    echo "[OK] Moove theme already present."
else
    echo "[INFO] Moove theme not found. Downloading $THEME_BRANCH from $THEME_REPO ..."
    mkdir -p "$MOODLE_DIR/theme"
    if curl -fsSL "$THEME_ZIP_URL" -o /tmp/moove.zip && \
       unzip -q /tmp/moove.zip -d /tmp && \
       mv /tmp/moodle-theme_moove-MOODLE_501_STABLE "$THEME_DEST"; then
        echo "[OK] Moove theme downloaded and extracted to $THEME_DEST"
        rm -f /tmp/moove.zip
        rm -rf /tmp/moodle-theme_moove-MOODLE_501_STABLE
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

echo "[INFO] Ensuring theme_boost is available for Moove..."
if [ -d "$BOOTSTHEME_PUBLIC_DEST" ] && [ ! -d "$BOOTSTHEME_DEST" ]; then
    echo "[INFO] Copying public/theme/boost to theme/boost for compatibility..."
    mkdir -p "$MOODLE_DIR/theme"
    cp -a "$BOOTSTHEME_PUBLIC_DEST" "$BOOTSTHEME_DEST"
elif [ ! -d "$BOOTSTHEME_DEST" ] && [ ! -d "$BOOTSTHEME_PUBLIC_DEST" ]; then
    echo "[WARN] theme_boost not found in either theme/boost or public/theme/boost"
fi

echo "[INFO] Checking Moove theme version compatibility..."
MOODLE_VERSION=""
if [ -f "$MOODLE_DIR/public/version.php" ]; then
    MOODLE_VERSION=$(php -r "require '$MOODLE_DIR/public/version.php'; echo preg_replace('/[^0-9].*/', '', \$version);")
elif [ -f "$MOODLE_DIR/version.php" ]; then
    MOODLE_VERSION=$(php -r "require '$MOODLE_DIR/version.php'; echo preg_replace('/[^0-9].*/', '', \$version);")
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

    if [ -f "$BOOTSTHEME_DEST/version.php" ]; then
        echo "[INFO] Patching $BOOTSTHEME_DEST/version.php for compatibility..."
        sed -i "s/\$plugin->requires = [0-9]*;/\$plugin->requires = $MOODLE_VERSION;/" "$BOOTSTHEME_DEST/version.php" || true
        echo "[OK] Patched $BOOTSTHEME_DEST/version.php"
    fi
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
