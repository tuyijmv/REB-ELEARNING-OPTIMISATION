#!/bin/bash

# A script to set up a Moodle instance and plugins from a JSON config file.
#
# REQUIREMENTS:
# - git: For cloning the repositories.
# - jq: For parsing the JSON config file.
#
# USAGE:
# 1. Customize 'plugins.json' with your desired Moodle plugins.
# 2. Make this script executable: chmod +x build.sh
# 3. Run the script: ./build.sh
#
# Plugins listed in plugins.json are installed into the Moodle 5.1+ web root.

set -e # Exit immediately if a command exits with a non-zero status.

CONFIG_FILE="plugins.json"
DEST_FOLDER="moodle_app"
MOODLE_BRANCH="MOODLE_501_STABLE"

# --- Helper Functions ---

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Clone a plugin repository, trying the requested branch/tag first and then
# falling back to the fallback_version if it fails.
clone_plugin() {
  local repo="$1" dest="$2" branch="$3" fallback="$4"

  for attempt in 1 2; do
    if [ "$attempt" -eq 1 ]; then
      echo "     - Cloning branch/tag: $branch"
      if git clone --depth 1 --branch "$branch" --recursive "$repo" "$dest" 2>/dev/null; then
        return 0
      fi
      echo "     - [WARN] Branch/tag '$branch' not found, trying fallback."
    else
      if [ -n "$fallback" ]; then
        echo "     - Cloning fallback branch/tag: $fallback"
        if git clone --depth 1 --branch "$fallback" --recursive "$repo" "$dest" 2>/dev/null; then
          return 0
        fi
        echo "     - [ERROR] Failed to clone $repo with branch '$branch' or fallback '$fallback'."
      else
        echo "     - [ERROR] Failed to clone $repo with branch '$branch'."
      fi
      return 1
    fi
  done
}

# --- Main Script ---

echo "Starting Moodle setup..."

# 1. Check for dependencies
if ! command_exists git; then
  echo "Error: 'git' is not installed. Please install git and try again."
  exit 1
fi

if ! command_exists jq; then
  echo "Error: 'jq' is not installed. Please install jq and try again."
  echo "On Debian/Ubuntu: sudo apt-get install jq"
  echo "On macOS (with Homebrew): brew install jq"
  exit 1
fi

# 2. Resolve configuration file
if [ ! -f "$CONFIG_FILE" ]; then
  for candidate in plugins.json config.json moodle-config.json; do
    if [ -f "$candidate" ]; then
      CONFIG_FILE="$candidate"
      break
    fi
  done
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file 'plugins.json' not found. Tried: plugins.json, config.json, moodle-config.json"
  exit 1
fi

# 3. Read plugin count
PLUGINS_COUNT=$(jq -r '.plugins | length' "$CONFIG_FILE")
PLUGINS_COUNT=${PLUGINS_COUNT:-0}

echo "Configuration loaded:"
echo "  - Moodle Branch: $MOODLE_BRANCH"
echo "  - Plugins to install: $PLUGINS_COUNT"
echo "  - Destination: $DEST_FOLDER"

# 4. Check if destination folder already exists
if [ -d "$DEST_FOLDER" ]; then
  echo "Warning: Destination folder '$DEST_FOLDER' already exists. Removing..."
  rm -rf "$DEST_FOLDER"
fi

# 5. Clone Moodle core
echo "----------------------------------------"
echo "Cloning Moodle core (branch: $MOODLE_BRANCH)..."
git clone --depth 1 --branch "$MOODLE_BRANCH" https://github.com/moodle/moodle.git "$DEST_FOLDER"
echo "Moodle core downloaded successfully."

# 6. Clone all plugins
if [ "$PLUGINS_COUNT" -gt 0 ]; then
  echo "----------------------------------------"
  echo "Installing plugins..."

  cd "$DEST_FOLDER"

  # Track unique destinations to avoid double-cloning.
  : > /tmp/reb_plugin_destinations

  for i in $(jq -c '.plugins[]?' "$CONFIG_FILE"); do
    PLUGIN_NAME=$(echo "$i" | jq -r '.name // "unknown"')
    PLUGIN_REPO=$(echo "$i" | jq -r '.repo // .repository // empty')
    PLUGIN_BRANCH=$(echo "$i" | jq -r '.branch // empty')
    PLUGIN_FALLBACK=$(echo "$i" | jq -r '.fallback_version // .version // empty')
    PLUGIN_DEST=$(echo "$i" | jq -r '.dest // .destination // empty')

    if [ -z "$PLUGIN_REPO" ] || [ -z "$PLUGIN_DEST" ]; then
      echo "  -> [SKIP] Plugin '$PLUGIN_NAME' is missing repository or destination."
      continue
    fi

    if [ -z "$PLUGIN_BRANCH" ]; then
      PLUGIN_BRANCH="MOODLE_501_STABLE"
    fi

    # Normalise destination: ensure it lives under the Moodle 5.1+ web root.
    case "$PLUGIN_DEST" in
      public/*) ;;
      *) PLUGIN_DEST="public/$PLUGIN_DEST" ;;
    esac

    # De-duplicate by normalised destination.
    if grep -qxF "$PLUGIN_DEST" /tmp/reb_plugin_destinations 2>/dev/null; then
      echo "  -> [SKIP] Plugin '$PLUGIN_NAME' (destination '$PLUGIN_DEST' already installed)."
      continue
    fi
    echo "$PLUGIN_DEST" >> /tmp/reb_plugin_destinations

    echo "  -> Installing plugin: $PLUGIN_NAME"
    echo "     - Repository: $PLUGIN_REPO"
    echo "     - Branch: $PLUGIN_BRANCH"
    echo "     - Fallback version: ${PLUGIN_FALLBACK:-none}"
    echo "     - Destination: $PLUGIN_DEST"

    mkdir -p "$(dirname "$PLUGIN_DEST")"
    if clone_plugin "$PLUGIN_REPO" "$PLUGIN_DEST" "$PLUGIN_BRANCH" "$PLUGIN_FALLBACK"; then
      echo "     - Plugin '$PLUGIN_NAME' installed."
    fi
  done

  rm -f /tmp/reb_plugin_destinations
  cd ..
fi

rm -f "$PLUGIN_MANIFEST" 2>/dev/null || true

echo "----------------------------------------"
echo "✅ Moodle setup complete!"
echo "Your Moodle project is ready in the '$DEST_FOLDER' directory."
echo ""
echo "Next steps:"
echo "1. Create a database for Moodle."
echo "2. Create a 'moodledata' directory outside of your web root."
echo "3. Run docker compose up -d"
echo "4. Visit your Moodle site in a web browser to start the installation process."
