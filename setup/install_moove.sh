#!/bin/bash
set -e

MOODLE_DIR="/var/www/html/moodle_app"
THEME_DIR="$MOODLE_DIR/theme/moove"

echo "[Moove] Installing Moove theme from MOODLE_501_STABLE branch..."

# 1. Remove existing folder if present
if [ -d "$THEME_DIR" ]; then
    echo "[Moove] Removing existing moove directory..."
    rm -rf "$THEME_DIR"
fi

# 2. Clone the compatible branch
git clone --depth 1 --branch MOODLE_501_STABLE \
    https://github.com/willianmano/moodle-theme_moove.git "$THEME_DIR"

# 3. Patch version.php to match the installed Moodle core version
#    (this prevents "version is too new" errors)
CORE_VERSION=$(grep -oP '(?<=\$version\s*=\s*")[0-9]+' "$MOODLE_DIR/version.php" || true)
if [ -n "$CORE_VERSION" ]; then
    echo "[Moove] Patching version.php to match core version $CORE_VERSION..."
    sed -i "s/\(\$version\s*=\s*\"\)[0-9]*\"/\1$CORE_VERSION\"/" "$THEME_DIR/version.php"
else
    echo "[Moove] Warning: Could not extract core version, skipping patch."
fi

# 4. Set ownership (www-data is the web user)
chown -R www-data:www-data "$THEME_DIR"

# 5. Run the Moodle upgrade to register the theme
echo "[Moove] Running upgrade.php to register the theme..."
php "$MOODLE_DIR/admin/cli/upgrade.php" --non-interactive

# 6. Set Moove as the default theme
echo "[Moove] Setting Moove as default theme..."
php "$MOODLE_DIR/admin/cli/cfg.php" --name=theme --set=moove

# 7. Purge caches to apply changes immediately
echo "[Moove] Purging caches..."
php "$MOODLE_DIR/admin/cli/purge_caches.php"

echo "[Moove] Installation complete!"
