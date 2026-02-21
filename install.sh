#!/usr/bin/env bash
set -euo pipefail

REPO_NAME="airscan-web"
REPO_URL="https://github.com/comcy/airscan-web.git"
# Determine the target directory for cloning/updating.
# Prioritize current directory if airscan-web already exists there,
# otherwise use HOME directory to prevent cluttering current working directory.
if [ -d "./$REPO_NAME" ]; then
    TARGET_DIR="$(pwd)/$REPO_NAME"
elif [ -d "$HOME/$REPO_NAME" ]; then
    TARGET_DIR="$HOME/$REPO_NAME"
else
    TARGET_DIR="$HOME/$REPO_NAME"
fi


echo "Starting Airscan-Web Installation/Update Script..."
echo "Target directory for repository: $TARGET_DIR"

if [ -d "$TARGET_DIR" ]; then
    echo "Repository '$REPO_NAME' found at '$TARGET_DIR'."
    echo "Attempting to update by pulling latest changes..."
    cd "$TARGET_DIR" || { echo "ERROR: Could not change to directory $TARGET_DIR"; exit 1; }
    git pull || { echo "WARNING: Failed to pull latest updates. Continuing with existing version."; }
else
    echo "Repository '$REPO_NAME' not found."
    echo "Cloning into '$TARGET_DIR'..."
    # Ensure parent directory exists if target is not current directory
    mkdir -p "$(dirname "$TARGET_DIR")"
    git clone "$REPO_URL" "$TARGET_DIR" || { echo "ERROR: Failed to clone repository from $REPO_URL."; exit 1; }
    cd "$TARGET_DIR" || { echo "ERROR: Could not change to directory $TARGET_DIR after cloning"; exit 1; }
fi

echo "Executing setup script from '$TARGET_DIR'..."
# Ensure setup.sh is executable
chmod +x setup.sh || { echo "ERROR: Could not make setup.sh executable."; exit 1; }
./setup.sh || { echo "ERROR: The setup.sh script failed to execute successfully."; exit 1; }

echo "Airscan-Web Installation/Update process completed."
