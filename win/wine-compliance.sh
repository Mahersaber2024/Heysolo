#!/usr/bin/env bash
# ============================================================================
# wine-compliance.sh - Standardize Wine prefixes to match genuine Windows builds
# ============================================================================
# This module aligns Wine prefixes with standard Windows profiles so that
# MT5 terminals report a consistent, supported Windows environment.
#
# WHAT IT DOES:
# - Aligns Windows version in registry to a standard build (default: Win10 Pro 22H2 build 19045)
# - Version/build is customizable: presets 1-9, custom build, or WIN_BUILD=...
# - Removes non-standard registry keys and DLLs
# - Configures standard DLL loading order (ntdll, kernel32, etc.)
# - Normalizes process names and environment artifacts
# - Standardizes User-Agent for HTTP requests
# - Cleans up non-standard environment variables
#
# USAGE:
#   sudo bash wine-compliance.sh              # Interactive menu
#   sudo bash wine-compliance.sh apply        # Apply to all terminals
#   sudo bash wine-compliance.sh apply <slug> # Apply to specific terminal
#   sudo bash wine-compliance.sh test         # Test compliance on all terminals
#   sudo bash wine-compliance.sh test <slug>  # Test specific terminal
#   sudo bash wine-compliance.sh revert       # Revert compliance patches
# ============================================================================
set -uo pipefail

# Configuration
MT5_USER="${MT5_USER:-mt5user}"
STATE_DIR="/etc/heysolo-mt5"
TERMINALS_FILE="${STATE_DIR}/terminals.list"
COMPLIANCE_STATE_FILE="${STATE_DIR}/compliance-applied.list"
LOG_FILE="/var/log/wine-compliance.log"
PROFILE_FILE="${STATE_DIR}/compliance-profile.conf"

# ============================================================================
# WINDOWS PROFILES - fully customizable
# ============================================================================
# label | build | release | product | edition | winver | buildlab
WIN_PRESETS=(
"Windows 10 Pro 22H2         |19045|22H2|Microsoft Windows 10 Pro|Professional|win10|19041.vb_release.191206-1406"
"Windows 10 Pro 21H2         |19044|21H2|Microsoft Windows 10 Pro|Professional|win10|19041.vb_release.191206-1406"
"Windows 10 Pro 21H1         |19043|21H1|Microsoft Windows 10 Pro|Professional|win10|19041.vb_release.191206-1406"
"Windows 10 Pro 20H2         |19042|20H2|Microsoft Windows 10 Pro|Professional|win10|19041.vb_release.191206-1406"
"Windows 10 Pro 2004         |19041|2004|Microsoft Windows 10 Pro|Professional|win10|19041.vb_release.191206-1406"
"Windows 10 Enterprise 22H2  |19045|22H2|Microsoft Windows 10 Enterprise|Enterprise|win10|19041.vb_release.191206-1406"
"Windows 10 Home 22H2        |19045|22H2|Microsoft Windows 10 Home|Core|win10|19041.vb_release.191206-1406"
"Windows 11 Pro 23H2         |22631|23H2|Microsoft Windows 11 Pro|Professional|win11|22621.ni_release.220506-1250"
"Windows 11 Pro 22H2         |22621|22H2|Microsoft Windows 11 Pro|Professional|win11|22621.ni_release.220506-1250"
)
DEFAULT_PRESET=1   # profile used when you just press Enter

# Active values (overridden by the saved profile / env vars / your choice)
WIN10_VERSION="10.0"
WIN10_BUILD="19045"
WIN10_RELEASE="22H2"
WIN10_PRODUCT="Microsoft Windows 10 Pro"
WIN10_EDITION="Professional"
WIN10_WINVER="win10"
WIN10_BUILDLAB="19041.vb_release.191206-1406"

# Apply one preset by its number
set_profile_from_preset() {
local n="$1" line
(( n >= 1 && n <= ${#WIN_PRESETS[@]} )) || return 1
line="${WIN_PRESETS[$((n-1))]}"
IFS='|' read -r _label WIN10_BUILD WIN10_RELEASE WIN10_PRODUCT WIN10_EDITION WIN10_WINVER WIN10_BUILDLAB <<< "$line"
return 0
}

save_profile() {
mkdir -p "$(dirname "$PROFILE_FILE")" 2>/dev/null || true
cat > "$PROFILE_FILE" <<EOF
# Wine compliance Windows profile - edit freely, or use the menu
WIN10_BUILD="${WIN10_BUILD}"
WIN10_RELEASE="${WIN10_RELEASE}"
WIN10_PRODUCT="${WIN10_PRODUCT}"
WIN10_EDITION="${WIN10_EDITION}"
WIN10_WINVER="${WIN10_WINVER}"
WIN10_BUILDLAB="${WIN10_BUILDLAB}"
EOF
}

load_profile() {
set_profile_from_preset "${DEFAULT_PRESET}"
# saved profile wins over the built-in default
[[ -s "$PROFILE_FILE" ]] && . "$PROFILE_FILE" 2>/dev/null || true
# env vars win over everything:  WIN_BUILD=21327 bash wine-compliance.sh apply
WIN10_BUILD="${WIN_BUILD:-$WIN10_BUILD}"
WIN10_RELEASE="${WIN_RELEASE:-$WIN10_RELEASE}"
WIN10_PRODUCT="${WIN_PRODUCT:-$WIN10_PRODUCT}"
WIN10_EDITION="${WIN_EDITION:-$WIN10_EDITION}"
WIN10_WINVER="${WIN_WINVER:-$WIN10_WINVER}"
}

current_profile_line() {
echo "${WIN10_PRODUCT} build ${WIN10_BUILD} (${WIN10_RELEASE})"
}

# Pick a Windows version - Enter keeps the current one
choose_profile() {
local i=1 label rest CH build rel prod ed
echo
header
title "WINDOWS VERSION PROFILE"
header
echo
echo -e "  current: ${BOLD}$(current_profile_line)${NC}"
echo
for line in "${WIN_PRESETS[@]}"; do
IFS='|' read -r label build rest <<< "$line"
printf "  ${BOLD}%2d)${NC} %s  build %s\n" "$i" "$label" "$build"
((i++))
done
echo -e "  ${BOLD} C)${NC} Custom - type your own build number / product name"
echo
read -rp "Choice [${BOLD}Enter = keep current${NC}]: " CH || CH=""
[[ -z "$CH" ]] && { info "Keeping $(current_profile_line)"; return 0; }
if [[ "${CH,,}" == "c" ]]; then
read -rp "  Build number       [${WIN10_BUILD}]: " build || build=""
read -rp "  Release/version    [${WIN10_RELEASE}]: " rel || rel=""
read -rp "  Product name       [${WIN10_PRODUCT}]: " prod || prod=""
read -rp "  Edition            [${WIN10_EDITION}]: " ed || ed=""
WIN10_BUILD="${build:-$WIN10_BUILD}"
WIN10_RELEASE="${rel:-$WIN10_RELEASE}"
WIN10_PRODUCT="${prod:-$WIN10_PRODUCT}"
WIN10_EDITION="${ed:-$WIN10_EDITION}"
if (( WIN10_BUILD >= 22000 )) 2>/dev/null; then WIN10_WINVER="win11"; else WIN10_WINVER="win10"; fi
elif [[ "$CH" =~ ^[0-9]+$ ]] && set_profile_from_preset "$CH"; then
:
else
err "Invalid selection - keeping $(current_profile_line)"
return 1
fi
save_profile
ok "Profile set: $(current_profile_line)"
}

# Colors
if [[ -t 1 ]]; then
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'; BLUE=$'\033[0;34m'; NC=$'\033[0m'; BOLD=$'\033[1m'; DIM=$'\033[2m'
else
RED=''; GREEN=''; YELLOW=''; CYAN=''; BLUE=''; NC=''; BOLD=''; DIM=''
fi

info()  { echo -e "${CYAN}ℹ  $1${NC}"; }
ok()    { echo -e "${GREEN}✅ $1${NC}"; }
warn()  { echo -e "${YELLOW}⚠️  $1${NC}"; }
err()   { echo -e "${RED}❌ $1${NC}"; }
header(){ echo -e "${BLUE}${BOLD}═══════════════════════════════════════════════════${NC}"; }
title() { echo -e "${BOLD}$1${NC}"; }
log() {
local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

require_root() {
if [[ $EUID -ne 0 ]]; then
err "This script must be run as root (or with sudo)."
exit 1
fi
}

as_mt5() {
local cmd="$1"
# Disable mscoree (Mono/.NET) and mshtml (Gecko) before wine ever runs, so
# a fresh/uninitialized prefix never pops the "Wine Mono is missing" or
# "Gecko is missing" installer dialog. MT5 needs neither, and that dialog
# can hang indefinitely (no timeout of its own) if the download stalls.
local suppress="export WINEDLLOVERRIDES=\"mscoree=,mshtml=\";"
if [[ "${WINE_COMPLIANCE_DEBUG:-0}" == "1" ]]; then
if command -v runuser >/dev/null 2>&1; then
timeout 120 runuser -u "${MT5_USER}" -- bash -lc "export DISPLAY=:1; ${suppress} $cmd"
else
timeout 120 su "${MT5_USER}" -s /bin/bash -c "export DISPLAY=:1; ${suppress} $cmd"
fi
elif command -v runuser >/dev/null 2>&1; then
timeout 120 runuser -u "${MT5_USER}" -- bash -lc "export DISPLAY=:1; ${suppress} $cmd" 2>/dev/null
else
timeout 120 su "${MT5_USER}" -s /bin/bash -c "export DISPLAY=:1; ${suppress} $cmd" 2>/dev/null
fi
}

# Make sure a (headless) X display is available on :1 before we shell into
# wine at all. This has NOTHING to do with whether the MT5 app itself is
# open - it's just the virtual display wine's regedit/reg tools need to
# start up. Without it, wine doesn't error out, it hangs forever. If some
# other part of the system already starts Xvfb on :1, this is a no-op.
ensure_display() {
[[ -S /tmp/.X11-unix/X1 ]] && return 0
if ! command -v Xvfb >/dev/null 2>&1; then
warn "Xvfb not found - install it with: apt-get install -y xvfb"
return 1
fi
info "No display found on :1 - starting a headless Xvfb for this run..."
nohup runuser -u "${MT5_USER}" -- Xvfb :1 -screen 0 1024x768x16 >/var/log/xvfb-compliance.log 2>&1 &
disown 2>/dev/null || true
local waited=0
until [[ -S /tmp/.X11-unix/X1 ]]; do
sleep 0.5; ((waited++))
if (( waited > 20 )); then
err "Xvfb on :1 did not come up in time - see /var/log/xvfb-compliance.log"
return 1
fi
done
ok "Xvfb :1 is up"
}

# ============================================================================
# COMPLIANCE FUNCTIONS
# ============================================================================
# Generate Windows 10 registry alignment patch
generate_compliance_reg() {
local wineprefix="$1"
local reg_file="/tmp/wine-compliance-$$.reg"
cat > "$reg_file" <<EOF
Windows Registry Editor Version 5.00
; ============================================================================
; ${WIN10_PRODUCT} build ${WIN10_BUILD} (${WIN10_RELEASE}) - Wine Compliance Module
; ============================================================================
[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion]
"CurrentBuild"="${WIN10_BUILD}"
"CurrentBuildNumber"="${WIN10_BUILD}"
"CurrentVersion"="6.3"
"ProductName"="${WIN10_PRODUCT}"
"ReleaseId"="${WIN10_RELEASE}"
"EditionID"="${WIN10_EDITION}"
"InstallationType"="Client"
"BuildGUID"="ffffffff-ffff-ffff-ffff-ffffffffffff"
"BuildLab"="${WIN10_BUILDLAB}"
"BuildLabEx"="${WIN10_BUILD}.1.amd64fre.${WIN10_BUILDLAB#*.}"
"CompositionEditionID"="${WIN10_EDITION}"
"RegisteredOwner"="User"
"RegisteredOrganization"=""
"InstallDate"=dword:5f3b2c8d
[HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Windows]
"SpBuild"="${WIN10_BUILD}"
"SpLevel"=dword:00000000
[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion]
"Version"="${WIN10_VERSION}"
"BuildVersion"="${WIN10_BUILD}"
"SubBuildNumber"="0"
"ProgramFilesDir"="C:\\\\Program Files"
"ProgramFilesDir (x86)"="C:\\\\Program Files (x86)"
"CommonFilesDir"="C:\\\\Program Files\\\\Common Files"
[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders]
"Common AppData"="C:\\\\ProgramData"
"Common Documents"="C:\\\\Users\\\\Public\\\\Documents"
[HKEY_LOCAL_MACHINE\Hardware\Description\System\CentralProcessor\0]
"ProcessorNameString"="Intel(R) Core(TM) i7-10700K CPU @ 3.80GHz"
"VendorIdentifier"="GenuineIntel"
"Identifier"="Intel64 Family 6 Model 165 Stepping 5"
[HKEY_LOCAL_MACHINE\Hardware\Description\System\BIOS]
"BIOSVersion"="American Megatrends Inc. F.12"
"BIOSVendor"="American Megatrends Inc."
"BIOSReleaseDate"="05/12/2020"
[HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\Tcpip\Parameters]
"Hostname"="DESKTOP-WIN10"
"NV Hostname"="DESKTOP-WIN10"
; Remove non-standard keys
[-HKEY_LOCAL_MACHINE\Software\Wine]
[-HKEY_CURRENT_USER\Software\Wine]
; Standardize debug output
[HKEY_CURRENT_USER\Software\Wine\Debug]
"RelayExclude"="ntdll.LdrInit;kernel32.48;kernel32.49"
"RelayFromExclude"="wineboot;winemenubuilder"
EOF
echo "$reg_file"
}

# Apply compliance to a single Wine prefix
apply_compliance_to_prefix() {
local wineprefix="$1"
local slug="$2"
if [[ ! -d "$wineprefix" ]]; then
err "Wine prefix not found: $wineprefix"
return 1
fi
info "Applying compliance to ${slug} (${wineprefix})..."
ensure_display || { err "No usable display for ${slug} - aborting."; return 1; }

# Make sure the prefix is actually initialized before we touch its registry -
# on a brand-new/never-run prefix the base HKLM keys may not exist yet, which
# makes the import look like it "worked" but the later verification query
# finds nothing (build shows as NOT SET).
as_mt5 "WINEPREFIX='${wineprefix}' wineboot -u" >/dev/null 2>&1
as_mt5 "WINEPREFIX='${wineprefix}' wineserver -w" >/dev/null 2>&1

# Generate registry file
local reg_file
reg_file=$(generate_compliance_reg "$wineprefix")

# Import registry (silently - /S avoids the interactive Registry Editor GUI)
local import1_ok=1 import2_ok=1
as_mt5 "WINEPREFIX='${wineprefix}' wine regedit /S '${reg_file}'" >/dev/null 2>&1 || import1_ok=0
# Flush the wineserver so the write is committed before we verify it
as_mt5 "WINEPREFIX='${wineprefix}' wineserver -w" >/dev/null 2>&1

# Remove non-standard files
as_mt5 "WINEPREFIX='${wineprefix}' rm -f ~/.wine/dosdevices/c:/windows/system32/wine*.dll" 2>/dev/null || true

# Set Windows version for terminal64.exe
cat > "/tmp/wine-appdefaults-$$.reg" <<EOF
Windows Registry Editor Version 5.00
[HKEY_CURRENT_USER\Software\Wine\AppDefaults\terminal64.exe]
"Version"="${WIN10_WINVER}"
[HKEY_CURRENT_USER\Software\Wine\AppDefaults\terminal64.exe\DllOverrides]
"*ntdll"="native,builtin"
"*kernel32"="native,builtin"
"*user32"="native,builtin"
"*advapi32"="native,builtin"
"*shell32"="native,builtin"
"*ole32"="native,builtin"
"*oleaut32"="native,builtin"
"*msvcrt"="native,builtin"
"*rpcrt4"="native,builtin"
"*winemenubuilder.exe"=""
"*mscoree"=""
"*mshtml"=""
EOF
as_mt5 "WINEPREFIX='${wineprefix}' wine regedit /S '/tmp/wine-appdefaults-$$.reg'" >/dev/null 2>&1 || import2_ok=0

# Clean up temp files
rm -f "$reg_file" "/tmp/wine-appdefaults-$$.reg"

# Verify the import actually landed, instead of assuming success
local win_build
win_build=$(as_mt5 "WINEPREFIX='${wineprefix}' wine cmd /c 'reg query \"HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\" /v CurrentBuild'" 2>/dev/null | grep -oP '\d+' | tail -1)

if [[ ${import1_ok} -eq 1 && ${import2_ok} -eq 1 && "${win_build}" == "${WIN10_BUILD}" ]]; then
# Record that compliance was applied (only now that it's confirmed)
mkdir -p "$(dirname "$COMPLIANCE_STATE_FILE")"
grep -v "^${slug}|" "$COMPLIANCE_STATE_FILE" > "${COMPLIANCE_STATE_FILE}.tmp" 2>/dev/null || true
echo "${slug}|${wineprefix}|$(date +%s)" >> "$COMPLIANCE_STATE_FILE"
mv "${COMPLIANCE_STATE_FILE}.tmp" "$COMPLIANCE_STATE_FILE" 2>/dev/null || true
ok "Compliance applied to ${slug} (verified: build ${win_build})"
log "Compliance applied to ${slug} (${wineprefix}), verified build ${win_build}"
return 0
else
err "Compliance import failed for ${slug} - registry shows build '${win_build:-NOT SET}' (expected ${WIN10_BUILD}). Check that wine/regedit works for this prefix."
log "Compliance apply FAILED for ${slug} (${wineprefix}) - import1=${import1_ok} import2=${import2_ok} build=${win_build:-NOT SET}"
return 1
fi
}

# Test compliance on a Wine prefix
test_compliance_on_prefix() {
local wineprefix="$1"
local slug="$2"
if [[ ! -d "$wineprefix" ]]; then
err "Wine prefix not found: $wineprefix"
return 1
fi
echo
header
title "COMPLIANCE TEST: ${slug}"
header
local issues=0
ensure_display || { err "No usable display for ${slug} - aborting test."; return 1; }

# Test 1: Check Windows version in registry
info "Test 1: Windows version in registry..."
local win_version
win_version=$(as_mt5 "WINEPREFIX='${wineprefix}' wine cmd /c 'reg query \"HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\" /v CurrentBuild'" 2>/dev/null | grep -oP '\d+' | tail -1)
if [[ "$win_version" == "$WIN10_BUILD" ]]; then
ok "Windows build: ${win_version} (expected: ${WIN10_BUILD})"
else
err "Windows build: ${win_version:-NOT SET} (expected: ${WIN10_BUILD})"
((issues++))
fi

# Test 2: Check product name
info "Test 2: Product name..."
local product_name
product_name=$(as_mt5 "WINEPREFIX='${wineprefix}' wine cmd /c 'reg query \"HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\" /v ProductName'" 2>/dev/null | grep -oP '(?<=REG_SZ\s{4}).*' | tr -d '\r')
if [[ "$product_name" == *"$WIN10_PRODUCT"* ]]; then
ok "Product name: ${product_name}"
else
err "Product name: ${product_name:-NOT SET} (expected: ${WIN10_PRODUCT})"
((issues++))
fi

# Test 3: Check for non-standard registry keys
info "Test 3: Non-standard registry keys..."
local wine_keys
wine_keys=$(as_mt5 "WINEPREFIX='${wineprefix}' wine cmd /c 'reg query HKLM\\Software\\Wine'" 2>/dev/null)
if [[ -z "$wine_keys" ]]; then
ok "No non-standard registry keys found"
else
err "Non-standard registry keys still present"
((issues++))
fi

# Test 4: Check DLL overrides
info "Test 4: DLL overrides for terminal64.exe..."
local dll_override
dll_override=$(as_mt5 "WINEPREFIX='${wineprefix}' wine cmd /c 'reg query \"HKCU\\Software\\Wine\\AppDefaults\\terminal64.exe\" /v Version'" 2>/dev/null | grep -oP '(?<=REG_SZ\s{4}).*' | tr -d '\r')
if [[ "$dll_override" == "win10" ]]; then
ok "terminal64.exe version override: ${dll_override}"
else
err "terminal64.exe version override: ${dll_override:-NOT SET} (expected: win10)"
((issues++))
fi

# Test 5: Check environment variables
info "Test 5: Environment variables..."
local wine_debug
wine_debug=$(as_mt5 "WINEPREFIX='${wineprefix}' env | grep WINEDEBUG" 2>/dev/null)
if [[ -z "$wine_debug" ]]; then
ok "WINEDEBUG not set (good)"
else
warn "WINEDEBUG is set: ${wine_debug}"
fi

echo
if [[ $issues -eq 0 ]]; then
ok "All tests passed for ${slug} - compliance is configured correctly"
return 0
else
err "${issues} test(s) failed for ${slug} - compliance needs to be applied"
return 1
fi
}

# Revert compliance from a Wine prefix
revert_compliance_from_prefix() {
local wineprefix="$1"
local slug="$2"
if [[ ! -d "$wineprefix" ]]; then
err "Wine prefix not found: $wineprefix"
return 1
fi
info "Reverting compliance from ${slug}..."
ensure_display || { err "No usable display for ${slug} - aborting revert."; return 1; }

# Remove app-specific overrides
cat > "/tmp/wine-revert-$$.reg" <<EOF
Windows Registry Editor Version 5.00
[-HKEY_CURRENT_USER\Software\Wine\AppDefaults\terminal64.exe]
EOF
as_mt5 "WINEPREFIX='${wineprefix}' wine regedit /S '/tmp/wine-revert-$$.reg'" >/dev/null 2>&1
rm -f "/tmp/wine-revert-$$.reg"

# Verify the key is actually gone instead of assuming success
local leftover
leftover=$(as_mt5 "WINEPREFIX='${wineprefix}' wine cmd /c 'reg query \"HKCU\\Software\\Wine\\AppDefaults\\terminal64.exe\" /v Version'" 2>/dev/null | grep -oP '(?<=REG_SZ\s{4}).*' | tr -d '\r')

if [[ -z "${leftover}" ]]; then
# Remove from state file (only now that revert is confirmed)
if [[ -f "$COMPLIANCE_STATE_FILE" ]]; then
grep -v "^${slug}|" "$COMPLIANCE_STATE_FILE" > "${COMPLIANCE_STATE_FILE}.tmp" 2>/dev/null || true
mv "${COMPLIANCE_STATE_FILE}.tmp" "$COMPLIANCE_STATE_FILE" 2>/dev/null || true
fi
ok "Compliance reverted from ${slug}"
log "Compliance reverted from ${slug}"
return 0
else
err "Revert failed for ${slug} - terminal64.exe version override is still '${leftover}'."
log "Compliance revert FAILED for ${slug} (${wineprefix}) - leftover=${leftover}"
return 1
fi
}

# ============================================================================
# MAIN OPERATIONS
# ============================================================================
apply_compliance_all() {
if [[ ! -s "$TERMINALS_FILE" ]]; then
err "No terminals registered. Install MT5 terminals first."
return 1
fi
echo
header
title "APPLYING WINE COMPLIANCE TO ALL TERMINALS"
header
local success=0 failed=0
while IFS='|' read -r slug exe wineprefix termpath; do
[[ -z "${slug:-}" ]] && continue
[[ -z "${wineprefix:-}" ]] && continue
if apply_compliance_to_prefix "$wineprefix" "$slug"; then
((success++))
else
((failed++))
fi
done < "$TERMINALS_FILE"
echo
header
if [[ $failed -eq 0 ]]; then
ok "Compliance applied to ${success} terminal(s)"
else
warn "Compliance applied to ${success} terminal(s), ${failed} failed"
fi
header
info "Restart terminals to apply changes:"
echo "  sudo heysolo  ->  R1, R2, etc."
echo
}

test_compliance_all() {
if [[ ! -s "$TERMINALS_FILE" ]]; then
err "No terminals registered."
return 1
fi
local success=0 failed=0
while IFS='|' read -r slug exe wineprefix termpath; do
[[ -z "${slug:-}" ]] && continue
[[ -z "${wineprefix:-}" ]] && continue
if test_compliance_on_prefix "$wineprefix" "$slug"; then
((success++))
else
((failed++))
fi
done < "$TERMINALS_FILE"
echo
header
if [[ $failed -eq 0 ]]; then
ok "All ${success} terminal(s) passed compliance tests"
else
err "${failed} terminal(s) failed compliance tests"
fi
header
}

revert_compliance_all() {
if [[ ! -s "$TERMINALS_FILE" ]]; then
err "No terminals registered."
return 1
fi
echo
header
title "REVERTING WINE COMPLIANCE FROM ALL TERMINALS"
header
local success=0 failed=0
while IFS='|' read -r slug exe wineprefix termpath; do
[[ -z "${slug:-}" ]] && continue
[[ -z "${wineprefix:-}" ]] && continue
if revert_compliance_from_prefix "$wineprefix" "$slug"; then
((success++))
else
((failed++))
fi
done < "$TERMINALS_FILE"
echo
header
ok "Compliance reverted from ${success} terminal(s)"
header
}

show_status() {
echo
header
title "WINE COMPLIANCE STATUS"
header
if [[ ! -s "$TERMINALS_FILE" ]]; then
warn "No terminals registered."
return
fi
while IFS='|' read -r slug exe wineprefix termpath; do
[[ -z "${slug:-}" ]] && continue
local status="NOT CONFIGURED"
local status_color="$RED"
if [[ -f "$COMPLIANCE_STATE_FILE" ]]; then
if grep -q "^${slug}|" "$COMPLIANCE_STATE_FILE" 2>/dev/null; then
status="CONFIGURED"
status_color="$GREEN"
fi
fi
printf "  %-30s [%b%-13s%b]\n" "$slug" "$status_color" "$status" "$NC"
done < "$TERMINALS_FILE"
header
}

# ============================================================================
# INTERACTIVE MENU
# ============================================================================
main_menu() {
while true; do
clear 2>/dev/null || true
echo
header
title "🛡️  WINE COMPLIANCE MANAGER - Standardize Windows Environment"
header
echo
echo "  This module aligns Wine installations with standard Windows profiles for MT5 compatibility."
echo -e "  active profile: ${BOLD}$(current_profile_line)${NC}"
echo
echo -e "  ${BOLD}1)${NC} Apply compliance to ALL terminals   ${DIM}(default - just press Enter)${NC}"
echo -e "  ${BOLD}2)${NC} Test compliance on ALL terminals"
echo -e "  ${BOLD}3)${NC} Revert compliance from ALL terminals"
echo -e "  ${BOLD}4)${NC} Show status"
echo -e "  ${BOLD}5)${NC} Apply compliance to SPECIFIC terminal"
echo -e "  ${BOLD}6)${NC} Test compliance on SPECIFIC terminal"
echo -e "  ${BOLD}7)${NC} Change Windows version/build profile"
echo -e "  ${BOLD}0)${NC} Back to main menu"
echo
header
echo
read -rp "Choice [${BOLD}1${NC}]: " CH || CH=""
CH="${CH:-1}"   # just press Enter -> apply compliance to ALL terminals
case "$CH" in
1) apply_compliance_all; read -rp "Press Enter to continue..." _ ;;
2) test_compliance_all; read -rp "Press Enter to continue..." _ ;;
3)
echo
warn "This will revert all compliance patches."
read -rp "Are you sure? (y/N): " confirm || confirm=""
if [[ "${confirm,,}" == "y" ]]; then
revert_compliance_all
fi
read -rp "Press Enter to continue..." _
;;
4) show_status; read -rp "Press Enter to continue..." _ ;;
5)
echo
if [[ ! -s "$TERMINALS_FILE" ]]; then
err "No terminals registered."
read -rp "Press Enter to continue..." _
continue
fi
local i=1
declare -a SLUGS=()
while IFS='|' read -r slug exe wineprefix termpath; do
[[ -z "${slug:-}" ]] && continue
SLUGS+=("$slug|$wineprefix")
printf "  %2d) %s\n" "$i" "$slug"
((i++))
done < "$TERMINALS_FILE"
echo
read -rp "Which terminal? (number) [${BOLD}1${NC}]: " idx || idx=""
idx="${idx:-1}"
if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#SLUGS[@]} )); then
IFS='|' read -r slug wineprefix <<< "${SLUGS[$((idx-1))]}"
apply_compliance_to_prefix "$wineprefix" "$slug"
else
err "Invalid selection."
fi
read -rp "Press Enter to continue..." _
;;
6)
echo
if [[ ! -s "$TERMINALS_FILE" ]]; then
err "No terminals registered."
read -rp "Press Enter to continue..." _
continue
fi
local i=1
declare -a SLUGS=()
while IFS='|' read -r slug exe wineprefix termpath; do
[[ -z "${slug:-}" ]] && continue
SLUGS+=("$slug|$wineprefix")
printf "  %2d) %s\n" "$i" "$slug"
((i++))
done < "$TERMINALS_FILE"
echo
read -rp "Which terminal? (number) [${BOLD}1${NC}]: " idx || idx=""
idx="${idx:-1}"
if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#SLUGS[@]} )); then
IFS='|' read -r slug wineprefix <<< "${SLUGS[$((idx-1))]}"
test_compliance_on_prefix "$wineprefix" "$slug"
else
err "Invalid selection."
fi
read -rp "Press Enter to continue..." _
;;
7) choose_profile; read -rp "Press Enter to continue..." _ ;;
0) exit 0 ;;
*) warn "Invalid option."; sleep 1 ;;
esac
done
}

# ============================================================================
# COMMAND LINE INTERFACE
# ============================================================================
usage() {
echo "Usage: wine-compliance.sh [menu|apply|test|revert|status|version] [slug]"
echo
echo "Commands:"
echo "  menu              - Interactive menu (default)"
echo "  apply [slug]      - Apply compliance to all or specific terminal"
echo "  test [slug]       - Test compliance on all or specific terminal"
echo "  revert [slug]     - Revert compliance from all or specific terminal"
echo "  status            - Show compliance status for all terminals"
echo "  version [n|build] - Pick a Windows profile (preset number or build, e.g. 19045)"
echo
echo "Windows version is customizable - presets, or set it inline:"
echo "  sudo bash wine-compliance.sh version 19045      # Windows 10 Pro 22H2"
echo "  sudo bash wine-compliance.sh version 22631      # Windows 11 Pro 23H2"
echo "  sudo WIN_BUILD=19044 bash wine-compliance.sh apply"
}

# help never needs root
case "${1:-menu}" in
help|--help|-h) usage; exit 0 ;;
esac

require_root
load_profile

case "${1:-menu}" in
menu)
main_menu
;;
apply)
if [[ -n "${2:-}" ]]; then
# Apply to specific terminal
slug="$2"
wineprefix=$(awk -F'|' -v s="$slug" '$1==s{print $3; exit}' "$TERMINALS_FILE" 2>/dev/null)
if [[ -n "$wineprefix" ]]; then
apply_compliance_to_prefix "$wineprefix" "$slug"
else
err "Terminal not found: $slug"
exit 1
fi
else
apply_compliance_all
fi
;;
test)
if [[ -n "${2:-}" ]]; then
# Test specific terminal
slug="$2"
wineprefix=$(awk -F'|' -v s="$slug" '$1==s{print $3; exit}' "$TERMINALS_FILE" 2>/dev/null)
if [[ -n "$wineprefix" ]]; then
test_compliance_on_prefix "$wineprefix" "$slug"
else
err "Terminal not found: $slug"
exit 1
fi
else
test_compliance_all
fi
;;
revert)
if [[ -n "${2:-}" ]]; then
slug="$2"
wineprefix=$(awk -F'|' -v s="$slug" '$1==s{print $3; exit}' "$TERMINALS_FILE" 2>/dev/null)
if [[ -n "$wineprefix" ]]; then
revert_compliance_from_prefix "$wineprefix" "$slug"
else
err "Terminal not found: $slug"
exit 1
fi
else
revert_compliance_all
fi
;;
status)
show_status
;;
version|profile)
if [[ -n "${2:-}" ]]; then
if [[ "$2" =~ ^[0-9]{4,6}$ ]]; then
WIN10_BUILD="$2"
if (( WIN10_BUILD >= 22000 )); then WIN10_WINVER="win11"; else WIN10_WINVER="win10"; fi
save_profile; ok "Profile set: $(current_profile_line)"
elif set_profile_from_preset "$2"; then
save_profile; ok "Profile set: $(current_profile_line)"
else
err "Unknown preset/build: $2"; exit 1
fi
else
choose_profile
fi
;;
*)
usage
exit 1
;;
esac