#!/usr/bin/env bash
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo."; exit 1; }

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/wine-compliance.sh"
[[ -f "$SRC" ]] || { echo "Put wine-compliance.sh next to this script."; exit 1; }

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  for c in /opt/heysolo/scripts/wine-compliance.sh /opt/heysolo/wine/wine-compliance.sh \
           /opt/heysolo/wine-compliance.sh /usr/local/bin/wine-compliance.sh; do
    [[ -f "$c" ]] && TARGET="$c" && break
  done
fi
[[ -z "$TARGET" ]] && TARGET=$(find / -name 'wine-compliance.sh' -type f 2>/dev/null | grep -v "$SRC" | head -1)
if [[ -z "$TARGET" ]]; then
  TARGET=/opt/heysolo/scripts/wine-compliance.sh
  echo "No existing install found - installing fresh to $TARGET"
  mkdir -p "$(dirname "$TARGET")"
else
  cp -a "$TARGET" "${TARGET}.bak.$(date +%s)"
  echo "Backed up: ${TARGET}.bak.*"
fi

bash -n "$SRC" || { echo "Source script has a syntax error - aborting."; exit 1; }
install -m 0755 "$SRC" "$TARGET"
echo "Installed: $TARGET"

PROFILE=/etc/heysolo-mt5/compliance-profile.conf
mkdir -p /etc/heysolo-mt5
cat > "$PROFILE" <<PROF
WIN10_BUILD="26200"
WIN10_RELEASE="25H2"
WIN10_PRODUCT="Microsoft Windows 11 Pro"
WIN10_EDITION="Professional"
WIN10_WINVER="win11"
WIN10_BUILDLAB="26100.ge_release.240331-1435"
PROF
echo "Active profile reset to: Microsoft Windows 11 Pro build 26200 (25H2)"

WV=$(sudo -u "${MT5_USER:-mt5user}" wine --version 2>/dev/null | tr -d '\r')
echo
echo "Detected Wine: ${WV:-unknown}"
case "$WV" in
  *taging*) echo "-> staging build: HideWineExports works, the 'on Wine ...' suffix will disappear." ;;
  *)        echo "-> NOT staging: plain Wine ignores HideWineExports."
            echo "   The build will read 26200, but MT5 will still print 'on Wine ... Linux ...'."
            echo "   Fix it with either:"
            echo "     apt-get install --install-recommends winehq-staging"
            echo "   or the binary patch (stop the terminals first):"
            echo "     sudo bash $TARGET hidewine" ;;
esac
echo
echo "Next:  sudo heysolo  ->  S  ->  1   (you get the before/after preview, then Enter to apply)"
echo "Then restart the terminals and check the Journal tab."
