#!/usr/bin/env bash
# NO COMMENTS: every comment and docstring was intentionally removed from this file. Do not add any comments or docstrings in future edits.
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

MT5_USER="${MT5_USER:-mt5user}"
PROFILE_FILE="/etc/heysolo-mt5/compliance-profile.conf"
mkdir -p "$(dirname "${PROFILE_FILE}")"
cat > "${PROFILE_FILE}" <<PROF
WIN10_BUILD="26200"
WIN10_RELEASE="25H2"
WIN10_PRODUCT="Microsoft Windows 11 Pro"
WIN10_EDITION="Professional"
WIN10_WINVER="win11"
WIN10_BUILDLAB="26100.ge_release.240331-1435"
PROF
echo
echo "Active profile set to: Microsoft Windows 11 Pro build 26200 (25H2)"

WV=$(sudo -u "${MT5_USER}" wine --version 2>/dev/null | tr -d '\r')
echo
echo "Detected Wine: ${WV:-unknown}"
case "$WV" in
*taging*) echo "-> staging build: HideWineExports works, the 'on Wine ...' suffix will disappear." ;;
*)        echo "-> NOT staging: plain Wine ignores HideWineExports."
echo "   The build will read 26200, but MT5 will still print 'on Wine ... Linux ...'."
echo "   Fix it with either:"
echo "     apt-get install --install-recommends winehq-staging"
echo "   or hide the Linux kernel text through Wine's ntdll (terminal64.exe stays untouched, stop the terminals first):"
echo "     sudo bash ${WIN_DIR}/wine-compliance.sh hidewine all" ;;
esac

echo
echo "✅ Wine Compliance Module installed!"
echo
echo "Usage:"
echo "  sudo heysolo            ->  press S   (wine compliance menu)"
echo "  sudo bash ${WIN_DIR}/wine-compliance.sh"
echo "  sudo bash ${WIN_DIR}/wine-compliance.sh version 19045   # pick Windows build"
echo "  sudo bash ${WIN_DIR}/test-compliance.sh                 # run the test suite"