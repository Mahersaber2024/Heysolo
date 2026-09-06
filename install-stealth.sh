#!/bin/bash
# install-stealth.sh - Install the Wine stealth module

set -e

SCRIPTS_DIR="/opt/heysolo/scripts"
REPO_RAW="https://raw.githubusercontent.com/Mahersaber2024/Heysolo/main"

echo "Installing Wine Stealth Module..."

# Download the stealth script
curl -fsSL "${REPO_RAW}/wine-stealth.sh" -o "${SCRIPTS_DIR}/wine-stealth.sh"
chmod +x "${SCRIPTS_DIR}/wine-stealth.sh"

echo "✅ Wine Stealth Module installed!"
echo
echo "Usage:"
echo "  sudo bash ${SCRIPTS_DIR}/wine-stealth.sh"
echo
echo "Or from the main menu:"
echo "  sudo heysolo  ->  S (apply stealth)"
