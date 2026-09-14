#!/usr/bin/env bash
# ============================================================================
# win/install-compliance.sh - Install / update the Wine compliance module
# ============================================================================
# Everything Wine-compliance related lives in one folder:  <scripts>/win/
#   win/wine-compliance.sh    - the module itself
#   win/test-compliance.sh    - automated test suite
#   win/install-compliance.sh - this installer
#
# Usage:  sudo bash install-compliance.sh
# ============================================================================
set -uo pipefail

SCRIPTS_DIR="${SCRIPTS_DIR:-/opt/heysolo/scripts}"
WIN_DIR="${SCRIPTS_DIR}/win"
REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/Mahersaber2024/Heysolo/main}"
FILES=(wine-compliance.sh test-compliance.sh install-compliance.sh)

if [[ $EUID -ne 0 ]]; then
echo "Run as root:  sudo bash install-compliance.sh"
exit 1
fi

echo "Installing Wine Compliance Module into ${WIN_DIR} ..."
mkdir -p "${WIN_DIR}"

# If we were run from a local checkout, copy; otherwise download from the repo
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failed=0
for f in "${FILES[@]}"; do
if [[ -s "${HERE}/${f}" && "${HERE}" != "${WIN_DIR}" ]]; then
cp -f "${HERE}/${f}" "${WIN_DIR}/${f}" && echo "  [OK] ${f} (local)"
elif curl -fsSL "${REPO_RAW}/win/${f}" -o "${WIN_DIR}/${f}.part" 2>/dev/null \
&& [[ -s "${WIN_DIR}/${f}.part" ]]; then
mv -f "${WIN_DIR}/${f}.part" "${WIN_DIR}/${f}"; echo "  [OK] ${f} (downloaded)"
else
rm -f "${WIN_DIR}/${f}.part" 2>/dev/null || true
if [[ -s "${WIN_DIR}/${f}" ]]; then
echo "  [!]  ${f} kept (download failed)"
else
echo "  [ERROR] could not get ${f}"; failed=1
fi
fi
done

chmod +x "${WIN_DIR}"/*.sh 2>/dev/null || true

if (( failed )); then
echo
echo "Install incomplete - check the network or the repo path (${REPO_RAW}/win/)."
exit 1
fi

echo
echo "✅ Wine Compliance Module installed!"
echo
echo "Usage:"
echo "  sudo heysolo            ->  press S   (wine compliance menu)"
echo "  sudo bash ${WIN_DIR}/wine-compliance.sh"
echo "  sudo bash ${WIN_DIR}/wine-compliance.sh version 19045   # pick Windows build"
echo "  sudo bash ${WIN_DIR}/test-compliance.sh                 # run the test suite"