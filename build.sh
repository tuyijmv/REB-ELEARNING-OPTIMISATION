#!/bin/bash

# A script to set up a Moodle instance and plugins from a JSON config file.
#
# REQUIREMENTS:
# - git: For cloning the repositories.
# - jq: For parsing the JSON config file.
#
# USAGE:
# 1. Customize the 'config.json' file with your desired Moodle version and plugins.
# 2. Make this script executable: chmod +x build.sh
# 3. Run the script: ./build.sh

set -e # Exit immediately if a command exits with a non-zero status.

CONFIG_FILE="config.json"
DEST_FOLDER="moodle_app"

# --- Helper Functions ---

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
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

# 2. Read configuration from JSON file
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file '$CONFIG_FILE' not found."
  exit 1
fi

MOODLE_BRANCH=$(jq -r '.moodle_branch' "$CONFIG_FILE")
PLUGINS_COUNT=$(jq '.plugins | length' "$CONFIG_FILE")

echo "Configuration loaded:"
echo "  - Moodle Branch: $MOODLE_BRANCH"
echo "  - Plugins to install: $PLUGINS_COUNT"
echo "  - Destination: $DEST_FOLDER"

# 3. Check if destination folder already exists
if [ -d "$DEST_FOLDER" ]; then
  echo "Warning: Destination folder '$DEST_FOLDER' already exists. Removing..."
  rm -rf "$DEST_FOLDER"
fi

# 4. Clone Moodle core
echo "----------------------------------------"
echo "Cloning Moodle core (branch: $MOODLE_BRANCH)..."
git clone --depth 1 --branch "$MOODLE_BRANCH" https://github.com/moodle/moodle.git "$DEST_FOLDER"
echo "Moodle core downloaded successfully."

# 5. Clone all plugins
if [ "$PLUGINS_COUNT" -gt 0 ]; then
  echo "----------------------------------------"
  echo "Installing plugins..."

  # Change to the Moodle directory to handle plugin paths correctly
  cd "$DEST_FOLDER"

  jq -c '.plugins[]' "../$CONFIG_FILE" | while read -r plugin; do
    PLUGIN_NAME=$(echo "$plugin" | jq -r '.name')
    PLUGIN_REPO=$(echo "$plugin" | jq -r '.repository')
    PLUGIN_VERSION=$(echo "$plugin" | jq -r '.version')
    PLUGIN_DEST=$(echo "$plugin" | jq -r '.destination')

    echo "  -> Installing plugin: $PLUGIN_NAME"
    echo "     - Repository: $PLUGIN_REPO"
    echo "     - Version: $PLUGIN_VERSION"
    echo "     - Destination: $PLUGIN_DEST"

    # Create parent directory if it doesn't exist (e.g., 'mod' or 'theme')
    mkdir -p "$(dirname "$PLUGIN_DEST")"

    # Clone the specific plugin branch/tag (with submodules)
    git clone --depth 1 --branch "$PLUGIN_VERSION" --recursive "$PLUGIN_REPO" "$PLUGIN_DEST"

    echo "     - Plugin '$PLUGIN_NAME' installed."
  done

  cd ..
fi

echo "----------------------------------------"
echo "✅ Moodle setup complete!"
echo "Your Moodle project is ready in the '$DEST_FOLDER' directory."
echo ""
echo "Next steps:"
echo "1. Create a database for Moodle."
echo "2. Create a 'moodledata' directory outside of your web root."
echo "3. Run docker compose up -d"
echo "4. Visit your Moodle site in a web browser to start the installation process."
