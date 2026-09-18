#!/usr/bin/env bash
# NO COMMENTS: every comment and docstring was intentionally removed from this file. Do not add any comments or docstrings in future edits.
set -uo pipefail

MT5_USER="${MT5_USER:-mt5user}"
STATE_DIR="/etc/heysolo-mt5"
TERMINALS_FILE="${STATE_DIR}/terminals.list"
COMPLIANCE_STATE_FILE="${STATE_DIR}/compliance-applied.list"
LOG_FILE="/var/log/wine-compliance.log"
PROFILE_FILE="${STATE_DIR}/compliance-profile.conf"

WIN_PRESETS=(
"Windows 11 Pro 25H2         |26200|25H2|Microsoft Windows 11 Pro|Professional|win11|26100.ge_release.240331-1435"
"Windows 11 Pro 24H2         |26100|24H2|Microsoft Windows 11 Pro|Professional|win11|26100.ge_release.240331-1435"
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
DEFAULT_PRESET=1

WIN10_VERSION="10.0"
WIN10_BUILD="26200"
WIN10_RELEASE="25H2"
WIN10_PRODUCT="Microsoft Windows 11 Pro"
WIN10_EDITION="Professional"
WIN10_WINVER="win11"
WIN10_BUILDLAB="26100.ge_release.240331-1435"

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
[[ -s "$PROFILE_FILE" ]] && . "$PROFILE_FILE" 2>/dev/null || true
WIN10_BUILD="${WIN_BUILD:-$WIN10_BUILD}"
WIN10_RELEASE="${WIN_RELEASE:-$WIN10_RELEASE}"
WIN10_PRODUCT="${WIN_PRODUCT:-$WIN10_PRODUCT}"
WIN10_EDITION="${WIN_EDITION:-$WIN10_EDITION}"
WIN10_WINVER="${WIN_WINVER:-$WIN10_WINVER}"
}

current_profile_line() {
echo "${WIN10_PRODUCT} build ${WIN10_BUILD} (${WIN10_RELEASE})"
}

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

step() {
local n="$1" total="$2" desc="$3" t0="$4"
local now elapsed
now=$(date +%s)
elapsed=$(( now - t0 ))
info "  [${n}/${total}] ${desc}... (${elapsed}s elapsed so far)"
log "  [${n}/${total}] ${desc}"
}

as_mt5() {
local cmd="$1"
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

generate_compliance_reg() {
local wineprefix="$1"
local reg_file="/tmp/wine-compliance-$$.reg"
cat > "$reg_file" <<EOF
Windows Registry Editor Version 5.00
[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion]
"CurrentBuild"="${WIN10_BUILD}"
"CurrentBuildNumber"="${WIN10_BUILD}"
"CurrentVersion"="6.3"
"ProductName"="${WIN10_PRODUCT}"
"ReleaseId"="${WIN10_RELEASE}"
"DisplayVersion"="${WIN10_RELEASE}"
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
"Hostname"="DESKTOP-7QK4L2M"
"NV Hostname"="DESKTOP-7QK4L2M"
[-HKEY_LOCAL_MACHINE\Software\Wine]
[-HKEY_CURRENT_USER\Software\Wine]
[HKEY_CURRENT_USER\Software\Wine]
"HideWineExports"="Y"
[HKEY_CURRENT_USER\Software\Wine\Debug]
"RelayExclude"="ntdll.LdrInit;kernel32.48;kernel32.49"
"RelayFromExclude"="wineboot;winemenubuilder"
EOF
echo "$reg_file"
}

wine_is_staging() {
local v
v=$(as_mt5 "wine --version" 2>/dev/null | tr -d '\r')
[[ "$v" == *[Ss]taging* ]]
}

wine_version_string() {
as_mt5 "wine --version" 2>/dev/null | tr -d '\r' | head -1
}

reg_get_raw() {
local file="$1" section="$2" key="$3"
[[ -f "$file" ]] || return 0
REG_SEC="$section" REG_KEY="$key" awk '
BEGIN { sec = ENVIRON["REG_SEC"]; k = "\"" ENVIRON["REG_KEY"] "\"=" }
/^\[/ { inside = (index($0, "[" sec "]") == 1); next }
inside && index($0, k) == 1 {
v = substr($0, length(k) + 1)
sub(/\r$/, "", v)
gsub(/^"|"$/, "", v)
print v
exit
}
' "$file" 2>/dev/null
}

current_wine_values() {
local wineprefix="$1"
local sysreg="${wineprefix}/system.reg"
local usrreg="${wineprefix}/user.reg"
local ntsec='Software\\Microsoft\\Windows NT\\CurrentVersion'
local appsec='Software\\Wine\\AppDefaults\\terminal64.exe'
CUR_BUILD=$(reg_get_raw "$sysreg" "$ntsec" "CurrentBuild")
CUR_BUILDNUM=$(reg_get_raw "$sysreg" "$ntsec" "CurrentBuildNumber")
CUR_PRODUCT=$(reg_get_raw "$sysreg" "$ntsec" "ProductName")
CUR_RELEASE=$(reg_get_raw "$sysreg" "$ntsec" "ReleaseId")
CUR_EDITION=$(reg_get_raw "$sysreg" "$ntsec" "EditionID")
CUR_WINVER=$(reg_get_raw "$usrreg" "$appsec" "Version")
CUR_HIDE=$(reg_get_raw "$usrreg" "$appsec" "HideWineExports")
[[ -z "$CUR_HIDE" ]] && CUR_HIDE=$(reg_get_raw "$usrreg" 'Software\\Wine' "HideWineExports")
}

diff_row() {
local label="$1" cur="$2" new="$3"
local shown_cur="${cur:-<not set>}"
if [[ "$cur" == "$new" ]]; then
printf "  %-22s %b%-32s%b %b(already correct)%b\n" "$label" "$GREEN" "$shown_cur" "$NC" "$DIM" "$NC"
else
printf "  %-22s %b%-32s%b %b->%b  %b%s%b\n" "$label" "$YELLOW" "$shown_cur" "$NC" "$DIM" "$NC" "$BOLD$GREEN" "$new" "$NC"
fi
}

preview_prefix_changes() {
local wineprefix="$1" slug="$2"
if [[ ! -d "$wineprefix" ]]; then
err "Wine prefix not found: $wineprefix"
return 1
fi
current_wine_values "$wineprefix"
local changes=0
[[ "$CUR_BUILD"    != "$WIN10_BUILD"   ]] && ((changes++))
[[ "$CUR_BUILDNUM" != "$WIN10_BUILD"   ]] && ((changes++))
[[ "$CUR_PRODUCT"  != "$WIN10_PRODUCT" ]] && ((changes++))
[[ "$CUR_RELEASE"  != "$WIN10_RELEASE" ]] && ((changes++))
[[ "$CUR_EDITION"  != "$WIN10_EDITION" ]] && ((changes++))
[[ "$CUR_WINVER"   != "$WIN10_WINVER"  ]] && ((changes++))
[[ "$CUR_HIDE"     != "Y"              ]] && ((changes++))
echo
echo -e "  ${BOLD}${slug}${NC} ${DIM}(${wineprefix})${NC}"
printf "  %-22s %-32s     %s\n" "FIELD" "CURRENT (real registry)" "WILL BECOME"
printf "  %s\n" "------------------------------------------------------------------------------"
diff_row "CurrentBuild"       "$CUR_BUILD"    "$WIN10_BUILD"
diff_row "CurrentBuildNumber" "$CUR_BUILDNUM" "$WIN10_BUILD"
diff_row "ProductName"        "$CUR_PRODUCT"  "$WIN10_PRODUCT"
diff_row "ReleaseId"          "$CUR_RELEASE"  "$WIN10_RELEASE"
diff_row "EditionID"          "$CUR_EDITION"  "$WIN10_EDITION"
diff_row "terminal64 Version" "$CUR_WINVER"   "$WIN10_WINVER"
diff_row "HideWineExports"    "$CUR_HIDE"     "Y"
echo
if (( changes == 0 )); then
ok "  ${slug}: nothing to change - already matches the profile"
else
info "  ${slug}: ${changes} value(s) will change"
fi
PREVIEW_CHANGES=$changes
return 0
}

confirm_preview() {
local n_changes="${1:-0}"
if [[ ! -t 0 ]]; then
return 0
fi
echo
header
if (( n_changes == 0 )); then
ok "Everything already matches the active profile. Applying again is harmless."
else
warn "${n_changes} registry value(s) will be overwritten across the terminals above."
fi
info "Nothing has been changed yet. This was a read-only look at the real Wine registry."
if wine_is_staging; then
ok "Wine is a staging build ($(wine_version_string)) - HideWineExports will work, the \"on Wine ...\" suffix will disappear."
else
warn "Wine is NOT a staging build ($(wine_version_string)) - HideWineExports is IGNORED by plain Wine."
warn "The build number will change, but MT5 will still print \"on Wine ... Linux ...\"."
info "To drop that suffix: install wine-staging, or run the terminal64.exe binary patch (option H)."
fi
header
echo
local ans=""
read -rp "$(echo -e "Press ${BOLD}Enter${NC} to apply, or type ${BOLD}n${NC} to cancel: ")" ans || ans=""
if [[ "${ans,,}" == "n" || "${ans,,}" == "no" ]]; then
warn "Cancelled - no changes made."
return 1
fi
return 0
}

wineprefix_busy_pids() {
local wineprefix="$1" envfile pid
for envfile in /proc/[0-9]*/environ; do
[[ -r "$envfile" ]] || continue
if tr '\0' '\n' < "$envfile" 2>/dev/null | grep -qxF "WINEPREFIX=${wineprefix}"; then
pid="${envfile#/proc/}"; pid="${pid%/environ}"
echo "$pid"
fi
done
}

apply_compliance_to_prefix() {
local wineprefix="$1"
local slug="$2"
local t0 total=8
t0=$(date +%s)
if [[ ! -d "$wineprefix" ]]; then
err "Wine prefix not found: $wineprefix"
return 1
fi
local busy_pids
busy_pids=$(wineprefix_busy_pids "$wineprefix" | tr '\n' ' ')
if [[ -n "${busy_pids// /}" ]]; then
err "${slug}: still running in this prefix (pid: ${busy_pids}) - stop it first (sudo heysolo -> Z, or the terminal's number) then retry. Skipping to avoid a multi-minute hang."
log "  ${slug}: SKIPPED - prefix busy, pids: ${busy_pids}"
return 1
fi
if [[ "${COMPLIANCE_PREVIEW_SHOWN:-0}" != "1" ]]; then
echo
header
title "CURRENT WINE REGISTRY (read-only preview)"
header
preview_prefix_changes "$wineprefix" "$slug" || return 1
confirm_preview "${PREVIEW_CHANGES:-0}" || return 1
COMPLIANCE_PREVIEW_SHOWN=1
fi

info "Applying compliance to ${slug} (${wineprefix})..."
log "Applying compliance to ${slug} (${wineprefix}) - started"

step 1 $total "Making sure a usable X display exists" "$t0"
ensure_display || { err "No usable display for ${slug} - aborting."; log "  [1/${total}] FAILED: no display"; return 1; }

step 2 $total "Booting/initializing the Wine prefix (wineboot -u)" "$t0"
as_mt5 "WINEPREFIX='${wineprefix}' wineboot -u" >/dev/null 2>&1

step 3 $total "Waiting for wineserver to settle" "$t0"
as_mt5 "WINEPREFIX='${wineprefix}' wineserver -w" >/dev/null 2>&1

step 4 $total "Generating the compliance registry file" "$t0"
local reg_file
reg_file=$(generate_compliance_reg "$wineprefix")

step 5 $total "Importing the main compliance registry (wine regedit)" "$t0"
local import1_ok=1 import2_ok=1
as_mt5 "WINEPREFIX='${wineprefix}' wine regedit /S '${reg_file}'" >/dev/null 2>&1 || import1_ok=0
as_mt5 "WINEPREFIX='${wineprefix}' wineserver -w" >/dev/null 2>&1
if [[ ${import1_ok} -eq 0 ]]; then
warn "  [5/${total}] main registry import reported an error (continuing to next step)"
log "  [5/${total}] main registry import FAILED"
fi

step 6 $total "Removing non-standard wine*.dll files" "$t0"
rm -f "${wineprefix}"/drive_c/windows/system32/wine*.dll 2>/dev/null || true

step 7 $total "Setting terminal64.exe AppDefaults (version + DLL overrides)" "$t0"
cat > "/tmp/wine-appdefaults-$$.reg" <<EOF
Windows Registry Editor Version 5.00
[HKEY_CURRENT_USER\Software\Wine\AppDefaults\terminal64.exe]
"Version"="${WIN10_WINVER}"
"HideWineExports"="Y"
[HKEY_CURRENT_USER\Software\Wine\AppDefaults\terminal64.exe\DllOverrides]
"*winemenubuilder.exe"=""
"*mscoree"=""
"*mshtml"=""
EOF
as_mt5 "WINEPREFIX='${wineprefix}' wine regedit /S '/tmp/wine-appdefaults-$$.reg'" >/dev/null 2>&1 || import2_ok=0
if [[ ${import2_ok} -eq 0 ]]; then
warn "  [7/${total}] AppDefaults registry import reported an error (continuing to verification)"
log "  [7/${total}] AppDefaults registry import FAILED"
fi

rm -f "$reg_file" "/tmp/wine-appdefaults-$$.reg"

step 8 $total "Verifying the import (reg query CurrentBuild)" "$t0"
local win_build
win_build=$(as_mt5 "WINEPREFIX='${wineprefix}' reg query \"HKLM\Software\Microsoft\Windows NT\CurrentVersion\" /v CurrentBuild" 2>/dev/null | grep -oP '\d+' | tail -1)

local total_time=$(( $(date +%s) - t0 ))
if [[ ${import1_ok} -eq 1 && ${import2_ok} -eq 1 && "${win_build}" == "${WIN10_BUILD}" ]]; then
mkdir -p "$(dirname "$COMPLIANCE_STATE_FILE")"
grep -v "^${slug}|" "$COMPLIANCE_STATE_FILE" > "${COMPLIANCE_STATE_FILE}.tmp" 2>/dev/null || true
echo "${slug}|${wineprefix}|$(date +%s)" >> "$COMPLIANCE_STATE_FILE"
mv "${COMPLIANCE_STATE_FILE}.tmp" "$COMPLIANCE_STATE_FILE" 2>/dev/null || true
ok "Compliance applied to ${slug} (verified: build ${win_build}, took ${total_time}s)"
log "Compliance applied to ${slug} (${wineprefix}), verified build ${win_build}, took ${total_time}s"
return 0
else
err "Compliance import failed for ${slug} after ${total_time}s - registry shows build '${win_build:-NOT SET}' (expected ${WIN10_BUILD}). Check that wine/regedit works for this prefix."
log "Compliance apply FAILED for ${slug} (${wineprefix}) - import1=${import1_ok} import2=${import2_ok} build=${win_build:-NOT SET} took=${total_time}s"
return 1
fi
}

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

info "Test 1: Windows version in registry..."
local win_version
win_version=$(as_mt5 "WINEPREFIX='${wineprefix}' reg query \"HKLM\Software\Microsoft\Windows NT\CurrentVersion\" /v CurrentBuild" 2>/dev/null | grep -oP '\d+' | tail -1)
if [[ "$win_version" == "$WIN10_BUILD" ]]; then
ok "Windows build: ${win_version} (expected: ${WIN10_BUILD})"
else
err "Windows build: ${win_version:-NOT SET} (expected: ${WIN10_BUILD})"
((issues++))
fi

info "Test 2: Product name..."
local product_name
product_name=$(as_mt5 "WINEPREFIX='${wineprefix}' reg query \"HKLM\Software\Microsoft\Windows NT\CurrentVersion\" /v ProductName" 2>/dev/null | sed -n 's/.*REG_SZ[[:space:]]*//p' | tr -d '\r')
if [[ "$product_name" == *"$WIN10_PRODUCT"* ]]; then
ok "Product name: ${product_name}"
else
err "Product name: ${product_name:-NOT SET} (expected: ${WIN10_PRODUCT})"
((issues++))
fi

info "Test 3: Non-standard registry keys..."
local wine_keys
wine_keys=$(as_mt5 "WINEPREFIX='${wineprefix}' reg query HKLM\Software\Wine" 2>/dev/null)
if [[ -z "$wine_keys" ]]; then
ok "No non-standard registry keys found"
else
err "Non-standard registry keys still present"
((issues++))
fi

info "Test 4: DLL overrides for terminal64.exe..."
local dll_override
dll_override=$(as_mt5 "WINEPREFIX='${wineprefix}' reg query \"HKCU\Software\Wine\AppDefaults\terminal64.exe\" /v Version" 2>/dev/null | sed -n 's/.*REG_SZ[[:space:]]*//p' | tr -d '\r')
if [[ "$dll_override" == "win10" ]]; then
ok "terminal64.exe version override: ${dll_override}"
else
err "terminal64.exe version override: ${dll_override:-NOT SET} (expected: win10)"
((issues++))
fi

info "Test 5: Wine exports hidden (the \"on Wine ...\" suffix)..."
local hide_val
hide_val=$(reg_get_raw "${wineprefix}/user.reg" 'Software\\Wine\\AppDefaults\\terminal64.exe' "HideWineExports")
[[ -z "$hide_val" ]] && hide_val=$(reg_get_raw "${wineprefix}/user.reg" 'Software\\Wine' "HideWineExports")
if [[ "${hide_val^^}" == "Y" ]]; then
if wine_is_staging; then
ok "HideWineExports=Y and Wine is staging - suffix should be gone"
else
warn "HideWineExports=Y but Wine is not staging ($(wine_version_string)) - suffix will remain"
((issues++))
fi
else
err "HideWineExports: ${hide_val:-NOT SET} (expected: Y)"
((issues++))
fi

info "Test 6: Environment variables..."
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

revert_compliance_from_prefix() {
local wineprefix="$1"
local slug="$2"
if [[ ! -d "$wineprefix" ]]; then
err "Wine prefix not found: $wineprefix"
return 1
fi
info "Reverting compliance from ${slug}..."
ensure_display || { err "No usable display for ${slug} - aborting revert."; return 1; }

cat > "/tmp/wine-revert-$$.reg" <<EOF
Windows Registry Editor Version 5.00
[-HKEY_CURRENT_USER\Software\Wine\AppDefaults\terminal64.exe]
EOF
as_mt5 "WINEPREFIX='${wineprefix}' wine regedit /S '/tmp/wine-revert-$$.reg'" >/dev/null 2>&1
rm -f "/tmp/wine-revert-$$.reg"

local leftover
leftover=$(as_mt5 "WINEPREFIX='${wineprefix}' reg query \"HKCU\Software\Wine\AppDefaults\terminal64.exe\" /v Version" 2>/dev/null | sed -n 's/.*REG_SZ[[:space:]]*//p' | tr -d '\r')

if [[ -z "${leftover}" ]]; then
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

apply_compliance_all() {
if [[ ! -s "$TERMINALS_FILE" ]]; then
err "No terminals registered. Install MT5 terminals first."
return 1
fi
echo
header
title "CURRENT WINE REGISTRY - ALL TERMINALS (read-only preview)"
header
echo -e "  active profile: ${BOLD}$(current_profile_line)${NC}"
local total_changes=0
while IFS='|' read -r p_slug p_exe p_prefix p_termpath; do
[[ -z "${p_slug:-}" ]] && continue
[[ -z "${p_prefix:-}" ]] && continue
if preview_prefix_changes "$p_prefix" "$p_slug"; then
total_changes=$(( total_changes + ${PREVIEW_CHANGES:-0} ))
fi
done < "$TERMINALS_FILE"
confirm_preview "$total_changes" || return 1
COMPLIANCE_PREVIEW_SHOWN=1

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
if ! wine_is_staging; then
warn "Wine is NOT a staging build ($(wine_version_string)) - HideWineExports is IGNORED by plain Wine."
info "To drop that suffix: install wine-staging, or run the terminal64.exe binary patch (option H)."
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

exe_is_running() {
local exe="$1" dir base p pid
dir="$(dirname "$exe")"; base="$(basename "$exe")"
for p in /proc/[0-9]*; do
pid="${p#/proc/}"
[[ "$pid" == "$$" ]] && continue
grep -Fq -- "$exe" "${p}/maps" 2>/dev/null && return 0
done
if pgrep -u "${MT5_USER}" -a -f "$base" 2>/dev/null | grep -Fq -- "$dir"; then return 0; fi
return 1
}

find_terminal_exe() {
find "${1}/drive_c" -maxdepth 6 -name 'terminal64.exe' -type f 2>/dev/null | head -1
}

hide_wine_state() {
local exe
exe="$(find_terminal_exe "$1")"
if [[ -z "$exe" ]]; then printf '%s' "${DIM}no terminal64.exe${NC}"; return 0; fi
if grep -qa 'hack_get_version' "$exe" 2>/dev/null; then
printf '%s' "${GREEN}patched${NC}"
elif [[ -f "${exe}.orig-wine-detect" ]]; then
printf '%s' "${YELLOW}restored${NC}"
else
printf '%s' "${DIM}not patched${NC}"
fi
}

hide_wine_binary_patch() {
local wineprefix="$1" slug="$2"
local exe
exe="$(find_terminal_exe "$wineprefix")"
if [[ -z "$exe" ]]; then
err "terminal64.exe not found under ${wineprefix}/drive_c for ${slug}"
return 1
fi
echo
info "${slug}: ${exe}"
if ! grep -qa 'wine_get_version' "$exe" 2>/dev/null; then
if grep -qa 'hack_get_version' "$exe" 2>/dev/null; then
ok "  already patched (hack_get_version present)"
return 0
fi
warn "  no wine_get_version string in this binary - nothing to patch"
return 0
fi
local bkp="${exe}.orig-wine-detect"
if [[ ! -f "$bkp" ]]; then
cp -a "$exe" "$bkp" || { err "  backup failed - aborting"; return 1; }
info "  backup: ${bkp}"
fi
if exe_is_running "$exe"; then
warn "  this terminal looks like it is running - stop only this one, then retry"
return 1
fi
sed -i 's/wine_get_version/hack_get_version/g; s/wine_get_host_version/hack_get_host_version/g; s/wine_get_build_id/hack_get_build_id/g' "$exe" 2>/dev/null
if grep -qa 'wine_get_version' "$exe" 2>/dev/null; then
err "  patch did not stick - restoring backup"
cp -a "$bkp" "$exe"
return 1
fi
ok "  patched - MT5 can no longer resolve wine_get_version"
return 0
}

hide_wine_confirm() {
warn "This edits terminal64.exe in place (a .orig-wine-detect backup is kept)."
warn "Only needed when Wine is NOT a staging build. Stop the affected terminal(s) first."
echo
local ans=""
[[ -t 0 ]] || return 0
read -rp "$(echo -e "Type ${BOLD}yes${NC} to proceed: ")" ans || ans=""
[[ "${ans,,}" == "yes" ]] && return 0
warn "Cancelled - no changes made."
return 1
}

hide_wine_apply_one() {
local slug="$1" wineprefix
wineprefix=$(awk -F'|' -v s="$slug" '$1==s{print $3; exit}' "$TERMINALS_FILE" 2>/dev/null)
if [[ -z "$wineprefix" ]]; then err "Terminal not found: $slug"; return 1; fi
hide_wine_binary_patch "$wineprefix" "$slug"
}

hide_wine_binary_patch_all() {
if [[ ! -s "$TERMINALS_FILE" ]]; then
err "No terminals registered."
return 1
fi
if [[ "${HW_SKIP_CONFIRM:-0}" != "1" ]]; then
echo
header
title "HIDE WINE FROM MT5 - terminal64.exe binary patch"
header
hide_wine_confirm || return 1
fi
local slug exe wineprefix termpath n_ok=0 n_fail=0
while IFS='|' read -r slug exe wineprefix termpath; do
[[ -z "${slug:-}" ]] && continue
[[ -z "${wineprefix:-}" ]] && continue
if hide_wine_binary_patch "$wineprefix" "$slug"; then ((n_ok++)); else ((n_fail++)); fi
done < "$TERMINALS_FILE"
echo
header
if (( n_fail == 0 )); then
ok "Done on ${n_ok} terminal(s). Restart them, then check the Journal tab."
else
warn "${n_ok} done, ${n_fail} failed."
fi
header
}

hide_wine_binary_patch_pick() {
local i=1 slug exe wineprefix termpath idx
declare -a HW_LIST=()
echo
while IFS='|' read -r slug exe wineprefix termpath; do
[[ -z "${slug:-}" ]] && continue
[[ -z "${wineprefix:-}" ]] && continue
HW_LIST+=("${slug}|${wineprefix}")
printf "  ${BOLD}%2d)${NC} %-28s [%b]\n" "$i" "$slug" "$(hide_wine_state "$wineprefix")"
((i++))
done < "$TERMINALS_FILE"
if (( ${#HW_LIST[@]} == 0 )); then
err "No terminals with a wine prefix."
return 1
fi
echo
read -rp "Which terminal? (number) [${BOLD}1${NC}]: " idx || idx=""
idx="${idx:-1}"
if [[ ! "$idx" =~ ^[0-9]+$ ]] || (( idx < 1 || idx > ${#HW_LIST[@]} )); then
err "Invalid selection."
return 1
fi
IFS='|' read -r slug wineprefix <<< "${HW_LIST[$((idx-1))]}"
echo
info "Selected: ${BOLD}${slug}${NC}"
hide_wine_confirm || return 1
if hide_wine_binary_patch "$wineprefix" "$slug"; then
echo
ok "Restart ${slug} only, then check its Journal tab."
fi
}

hide_wine_menu() {
if [[ ! -s "$TERMINALS_FILE" ]]; then
err "No terminals registered."
return 1
fi
local CH
echo
header
title "HIDE WINE FROM MT5 - terminal64.exe binary patch"
header
echo -e "  wine: ${BOLD}$(wine_version_string)${NC}"
echo
echo -e "  ${BOLD}1)${NC} All terminals"
echo -e "  ${BOLD}2)${NC} Pick one terminal from the list"
echo -e "  ${BOLD}0)${NC} Cancel"
echo
read -rp "Choice [${BOLD}1${NC}]: " CH || CH=""
CH="${CH:-1}"
case "${CH// /}" in
1) echo; hide_wine_confirm || return 1; HW_SKIP_CONFIRM=1 hide_wine_binary_patch_all ;;
2) hide_wine_binary_patch_pick ;;
0) info "Cancelled." ;;
*) err "Invalid selection." ;;
esac
}

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
echo -e "  ${BOLD}H)${NC} Hide Wine from MT5 (patch terminal64.exe)  ${DIM}(one terminal or all - non-staging Wine only)${NC}"
echo -e "  ${BOLD}0)${NC} Back to main menu"
echo
header
echo
read -rp "Choice [${BOLD}1${NC}]: " CH || CH=""
CH="${CH:-1}"
case "$CH" in
1) COMPLIANCE_PREVIEW_SHOWN=0; apply_compliance_all; read -rp "Press Enter to continue..." _ ;;
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
h|H) hide_wine_menu; read -rp "Press Enter to continue..." _ ;;
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
COMPLIANCE_PREVIEW_SHOWN=0
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

usage() {
echo "Usage: wine-compliance.sh [menu|apply|test|revert|status|version|hidewine] [slug]"
echo
echo "Commands:"
echo "  menu              - Interactive menu (default)"
echo "  apply [slug]      - Apply compliance to all or specific terminal"
echo "  test [slug]       - Test compliance on all or specific terminal"
echo "  revert [slug]     - Revert compliance from all or specific terminal"
echo "  status            - Show compliance status for all terminals"
echo "  version [n|build] - Pick a Windows profile (preset number or build, e.g. 19045)"
echo "  hidewine [slug]   - Patch terminal64.exe (no slug = menu: all or pick one)"
echo "  hidewine all      - Patch every terminal"
echo
echo "Windows version is customizable - presets, or set it inline:"
echo "  sudo bash wine-compliance.sh version 19045      # Windows 10 Pro 22H2"
echo "  sudo bash wine-compliance.sh version 22631      # Windows 11 Pro 23H2"
echo "  sudo WIN_BUILD=19044 bash wine-compliance.sh apply"
}

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
hidewine)
case "${2:-}" in
"") hide_wine_menu ;;
all) HW_SKIP_CONFIRM=1 hide_wine_binary_patch_all ;;
*) HW_SKIP_CONFIRM=1 hide_wine_apply_one "$2" ;;
esac
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