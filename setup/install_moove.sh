#!/bin/bash
set -e

MOODLE_DIR="/var/www/html/moodle_app"
THEME_NAME="moove"
THEME_DIR="$MOODLE_DIR/theme/$THEME_NAME"
THEME_PUBLIC_DIR="$MOODLE_DIR/public/theme/$THEME_NAME"
THEME_REPO="https://github.com/willianmano/moodle-theme_moove.git"
THEME_BRANCH="MOODLE_501_STABLE"
THEME_ZIP_URL="https://github.com/willianmano/moodle-theme_moove/archive/refs/heads/${THEME_BRANCH}.zip"

echo "[Moove] Installing Moove theme from ${THEME_BRANCH} branch..."

# 1. Remove existing folder if present
if [ -d "$THEME_DIR" ]; then
    echo "[Moove] Removing existing moove directory..."
    rm -rf "$THEME_DIR"
fi
if [ -d "$THEME_PUBLIC_DIR" ]; then
    echo "[Moove] Removing existing public/theme/moove directory..."
    rm -rf "$THEME_PUBLIC_DIR"
fi

# 2. Download and extract the compatible branch zip
echo "[Moove] Downloading ${THEME_BRANCH} from ${THEME_REPO} ..."
mkdir -p "$MOODLE_DIR/theme"
if curl -fsSL "$THEME_ZIP_URL" -o /tmp/moove.zip; then
    echo "[Moove] Download complete. Extracting..."
    if unzip -q /tmp/moove.zip -d /tmp/; then
        mv /tmp/moodle-theme_moove-${THEME_BRANCH} "$THEME_DIR"
        echo "[Moove] Theme extracted to $THEME_DIR"
        rm -f /tmp/moove.zip
    else
        echo "[Moove] [WARN] Failed to extract Moove zip. Trying git clone fallback..."
        rm -f /tmp/moove.zip
        if command -v git >/dev/null 2>&1; then
            git clone --depth 1 --branch "$THEME_BRANCH" "$THEME_REPO" "$THEME_DIR" || {
                echo "[Moove] [ERROR] Failed to clone Moove theme."
                exit 1
            }
        else
            echo "[Moove] [ERROR] git not available and zip extraction failed. Cannot install Moove."
            exit 1
        fi
    fi
else
    echo "[Moove] [WARN] Failed to download Moove zip. Trying git clone fallback..."
    if command -v git >/dev/null 2>&1; then
        git clone --depth 1 --branch "$THEME_BRANCH" "$THEME_REPO" "$THEME_DIR" || {
            echo "[Moove] [ERROR] Failed to clone Moove theme."
            exit 1
        }
    else
        echo "[Moove] [ERROR] Cannot download or clone Moove theme."
        exit 1
    fi
fi

# 3. Mirror to public/theme for Moodle 5.1+ compatibility
if [ -d "$THEME_DIR" ] && [ ! -d "$THEME_PUBLIC_DIR" ]; then
    echo "[Moove] Mirroring theme to public/theme for Moodle 5.1+ compatibility..."
    mkdir -p "$(dirname "$THEME_PUBLIC_DIR")"
    cp -a "$THEME_DIR" "$THEME_PUBLIC_DIR"
fi

# 4. Patch version.php to match the installed Moodle core version
#    (this prevents "version is too new" errors)
CORE_VERSION=""
if [ -f "$MOODLE_DIR/public/version.php" ]; then
    CORE_VERSION=$(php -r "require '$MOODLE_DIR/public/version.php'; echo preg_replace('/[^0-9].*/', '', \$version);" 2>/dev/null || true)
elif [ -f "$MOODLE_DIR/version.php" ]; then
    CORE_VERSION=$(php -r "require '$MOODLE_DIR/version.php'; echo preg_replace('/[^0-9].*/', '', \$version);" 2>/dev/null || true)
fi

if [ -n "$CORE_VERSION" ]; then
    echo "[Moove] Patching version.php to match core version $CORE_VERSION..."
    for theme_path in "$THEME_DIR" "$THEME_PUBLIC_DIR"; do
        if [ -f "$theme_path/version.php" ]; then
            sed -i "s/\$plugin->requires = [0-9]*;/\$plugin->requires = $CORE_VERSION;/" "$theme_path/version.php" || true
            echo "[Moove] Patched $theme_path/version.php"
        fi
    done
else
    echo "[Moove] Warning: Could not extract core version, skipping patch."
fi

# 5. Set ownership (www-data is the web user)
chown -R www-data:www-data "$THEME_DIR" 2>/dev/null || true
chown -R www-data:www-data "$THEME_PUBLIC_DIR" 2>/dev/null || true

# 6. Run the Moodle upgrade to register the theme
echo "[Moove] Running upgrade.php to register the theme..."
php "$MOODLE_DIR/admin/cli/upgrade.php" --non-interactive || {
    echo "[Moove] [WARN] upgrade.php reported issues (continuing)."
}

# 7. Set Moove as the default theme
echo "[Moove] Setting Moove as default theme..."
php "$MOODLE_DIR/admin/cli/cfg.php" --name=theme --set="$THEME_NAME"

# 8. Purge caches to apply changes immediately
echo "[Moove] Purging caches..."
php "$MOODLE_DIR/admin/cli/purge_caches.php"

echo "[Moove] Installation complete!"
