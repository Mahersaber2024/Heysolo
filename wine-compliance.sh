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
"Windows 11 Pro 25H2         |26200|25H2|Windows 11 Pro|Professional|win11|26100.ge_release.240331-1435"
"Windows 11 Pro 24H2         |26100|24H2|Windows 11 Pro|Professional|win11|26100.ge_release.240331-1435"
"Windows 10 Pro 22H2         |19045|22H2|Windows 10 Pro|Professional|win10|19041.vb_release.191206-1406"
"Windows 10 Pro 21H2         |19044|21H2|Windows 10 Pro|Professional|win10|19041.vb_release.191206-1406"
"Windows 10 Pro 21H1         |19043|21H1|Windows 10 Pro|Professional|win10|19041.vb_release.191206-1406"
"Windows 10 Pro 20H2         |19042|20H2|Windows 10 Pro|Professional|win10|19041.vb_release.191206-1406"
"Windows 10 Pro 2004         |19041|2004|Windows 10 Pro|Professional|win10|19041.vb_release.191206-1406"
"Windows 10 Enterprise 22H2  |19045|22H2|Windows 10 Enterprise|Enterprise|win10|19041.vb_release.191206-1406"
"Windows 10 Home 22H2        |19045|22H2|Windows 10 Home|Core|win10|19041.vb_release.191206-1406"
"Windows 11 Pro 23H2         |22631|23H2|Windows 11 Pro|Professional|win11|22621.ni_release.220506-1250"
"Windows 11 Pro 22H2         |22621|22H2|Windows 11 Pro|Professional|win11|22621.ni_release.220506-1250"
)
DEFAULT_PRESET=1

WIN10_VERSION="10.0"
WIN10_BUILD="26200"
WIN10_RELEASE="25H2"
WIN10_PRODUCT="Windows 11 Pro"
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
local t0 total=7
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

step 2 $total "Checking the Wine prefix is initialized" "$t0"
if [[ ! -f "${wineprefix}/system.reg" ]]; then
info "    first run for this prefix - initializing with wineboot"
as_mt5 "WINEPREFIX='${wineprefix}' wineboot -u" >/dev/null 2>&1
else
info "    prefix already initialized - skipping wineboot (it would reset prefix defaults)"
fi

step 3 $total "Backing up system.reg / user.reg" "$t0"
local bk="${wineprefix}/.compliance-regbackup"
mkdir -p "$bk" 2>/dev/null || true
local stamp
stamp=$(date +%Y%m%d-%H%M%S)
cp -p "${wineprefix}/system.reg" "${bk}/system.reg.${stamp}" 2>/dev/null || true
cp -p "${wineprefix}/user.reg"   "${bk}/user.reg.${stamp}"   2>/dev/null || true
chown -R "${MT5_USER}" "$bk" 2>/dev/null || true
info "    backup: ${bk} (stamp ${stamp})"
as_mt5 "WINEPREFIX='${wineprefix}' wineserver -w" >/dev/null 2>&1

step 4 $total "Generating the compliance registry file" "$t0"
local reg_file
reg_file=$(generate_compliance_reg "$wineprefix")

step 5 $total "Importing the main compliance registry (wine regedit)" "$t0"
local import1_ok=1 import2_ok=1
as_mt5 "WINEPREFIX='${wineprefix}' wine regedit /S '${reg_file}'" >/dev/null 2>&1 || import1_ok=0
as_mt5 "WINEPREFIX='${wineprefix}' wineserver -w" >/dev/null 2>&1
if [[ ${import1_ok} -eq 0 ]]; then
err "  [5/${total}] main registry import FAILED - aborting before anything else is touched."
log "  ${slug}: ABORTED - main registry import failed"
rm -f "$reg_file"
info "Nothing else was changed. Registry backup kept in ${bk}"
return 1
fi

step 6 $total "Setting terminal64.exe AppDefaults (version + DLL overrides)" "$t0"
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
err "  [6/${total}] AppDefaults registry import FAILED - aborting."
log "  ${slug}: ABORTED - AppDefaults import failed"
rm -f "$reg_file" "/tmp/wine-appdefaults-$$.reg"
info "Registry backup kept in ${bk}"
return 1
fi

rm -f "$reg_file" "/tmp/wine-appdefaults-$$.reg"

step 7 $total "Verifying the import (reg query CurrentBuild)" "$t0"
local win_build
win_build=$(as_mt5 "WINEPREFIX='${wineprefix}' reg query \"HKLM\Software\Microsoft\Windows NT\CurrentVersion\" /v CurrentBuild" 2>/dev/null | grep -oP '\d+' | tail -1)
if [[ -z "$win_build" ]]; then
info "    reg.exe returned nothing - falling back to reading system.reg directly"
win_build=$(reg_get_raw "${wineprefix}/system.reg" 'Software\\Microsoft\\Windows NT\\CurrentVersion' "CurrentBuild")
fi

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
err "Compliance import failed for ${slug} after ${total_time}s - registry shows build '${win_build:-NOT SET}' (expected ${WIN10_BUILD}). Restore with: cp ${bk}/system.reg.${stamp} ${wineprefix}/system.reg"
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

info "Test 3: DLL overrides for terminal64.exe..."
local dll_override
dll_override=$(as_mt5 "WINEPREFIX='${wineprefix}' reg query \"HKCU\Software\Wine\AppDefaults\terminal64.exe\DllOverrides\"" 2>/dev/null)
if [[ -n "$dll_override" ]]; then
ok "terminal64.exe DLL overrides present"
else
err "terminal64.exe DLL overrides NOT SET"
((issues++))
fi

info "Test 3b: Wine version override for terminal64.exe..."
local ver_override
ver_override=$(reg_get_raw "${wineprefix}/user.reg" 'Software\\Wine\\AppDefaults\\terminal64.exe' "Version")
if [[ "$ver_override" == "${WIN10_WINVER}" ]]; then
ok "terminal64.exe version override: ${ver_override}"
else
err "terminal64.exe version override: ${ver_override:-NOT SET} (expected: ${WIN10_WINVER})"
((issues++))
fi

info "Test 3c: Wine exports hidden (the \"on Wine ...\" suffix)..."
local hide_val
hide_val=$(reg_get_raw "${wineprefix}/user.reg" 'Software\\Wine\\AppDefaults\\terminal64.exe' "HideWineExports")
[[ -z "$hide_val" ]] && hide_val=$(reg_get_raw "${wineprefix}/user.reg" 'Software\\Wine' "HideWineExports")
if [[ "${hide_val^^}" == "Y" ]]; then
if wine_is_staging; then
ok "HideWineExports=Y and Wine is staging - suffix should be gone"
else
warn "HideWineExports=Y but Wine is not staging ($(wine_version_string)) - suffix will remain"
fi
else
err "HideWineExports: ${hide_val:-NOT SET} (expected: Y)"
((issues++))
fi

info "Test 4: Environment variables..."
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
leftover=$(reg_get_raw "${wineprefix}/user.reg" 'Software\\Wine\\AppDefaults\\terminal64.exe' "Version")

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

HW_LOG="${HW_LOG:-/var/log/heysolo-hidewine.log}"
HW_DIAG_SECS="${HW_DIAG_SECS:-45}"

hw_log_init() {
mkdir -p "$(dirname "$HW_LOG")" 2>/dev/null || true
if ! ( : >> "$HW_LOG" ) 2>/dev/null; then
HW_LOG="/tmp/heysolo-hidewine.log"
( : >> "$HW_LOG" ) 2>/dev/null || HW_LOG="/dev/null"
fi
chmod 644 "$HW_LOG" 2>/dev/null || true
}

hlog() {
local lvl="$1"; shift
local msg="$*"
printf '[%s] [%-4s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$lvl" "$msg" >> "$HW_LOG" 2>/dev/null || true
case "$lvl" in
ERR)  err "  $msg" ;;
WARN) warn "  $msg" ;;
OK)   ok "  $msg" ;;
STEP) echo -e "  ${CYAN}→ ${msg}${NC}" ;;
INFO) echo -e "  ${DIM}${msg}${NC}" ;;
DBG)  [[ "${HW_DEBUG:-0}" == "1" ]] && echo -e "    ${DIM}· ${msg}${NC}" ;;
esac
return 0
}

hw_run() {
local label="$1"; shift
local out rc
out="$("$@" 2>&1)"; rc=$?
hlog DBG "cmd[${label}] rc=${rc} :: $*"
if [[ -n "$out" ]]; then
while IFS= read -r line; do hlog DBG "    ${label}| ${line}"; done <<< "$out"
fi
return "$rc"
}

hw_sha() {
command -v sha256sum >/dev/null 2>&1 && sha256sum "$1" 2>/dev/null | awk '{print $1}' && return 0
echo "n/a"
}

hw_file_facts() {
local f="$1" tag="$2"
if [[ ! -e "$f" ]]; then hlog DBG "${tag}: MISSING ${f}"; return 1; fi
hlog DBG "${tag}: path=${f}"
hlog DBG "${tag}: stat=$(stat -c 'size=%s owner=%U:%G mode=%a mtime=%y' "$f" 2>/dev/null)"
hlog DBG "${tag}: sha256=$(hw_sha "$f")"
return 0
}

hw_terminal_log_path() {
local slug="$1" home
home="$(getent passwd "${MT5_USER}" 2>/dev/null | cut -d: -f6)"
home="${home:-/home/${MT5_USER}}"
echo "${home}/.heysolo/logs/${slug}.log"
}

hw_write_inplace() {
local src="$1" dst="$2"
if cat "$src" > "$dst" 2>/dev/null; then return 0; fi
return 1
}

hw_apply_bytes() {
local src="$1" dst="$2"
if command -v python3 >/dev/null 2>&1; then
python3 - "$src" "$dst" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
data = open(src, 'rb').read()
pairs = [(b'wine_get_host_version', b'hack_get_host_version'),
         (b'wine_get_build_id',     b'hack_get_build_id'),
         (b'wine_get_version',      b'hack_get_version')]
total = 0
for a, b in pairs:
    if len(a) != len(b):
        sys.exit(90)
    n = data.count(a)
    if n:
        data = data.replace(a, b)
        total += n
    print("replaced %s -> %s : %d" % (a.decode(), b.decode(), n))
open(dst, 'wb').write(data)
print("hits=%d bytes=%d" % (total, len(data)))
sys.exit(0 if total else 91)
PY
return $?
fi
if command -v perl >/dev/null 2>&1; then
perl -0777 -pe 's/wine_get_host_version/hack_get_host_version/g; s/wine_get_build_id/hack_get_build_id/g; s/wine_get_version/hack_get_version/g' "$src" > "$dst" 2>/dev/null
return $?
fi
LC_ALL=C sed -e 's/wine_get_host_version/hack_get_host_version/g' -e 's/wine_get_build_id/hack_get_build_id/g' -e 's/wine_get_version/hack_get_version/g' "$src" > "$dst" 2>/dev/null
return $?
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

hw_string_table() {
local f="$1"
if command -v python3 >/dev/null 2>&1; then
python3 - "$f" <<'PYSCAN'
import sys
path = sys.argv[1]
pairs = [(b'wine_get_version', b'hack_get_version'),
         (b'wine_get_host_version', b'hack_get_host_version'),
         (b'wine_get_build_id', b'hack_get_build_id')]
data = open(path, 'rb').read()
for a, b in pairs:
    offs = []
    i = data.find(a)
    while i != -1 and len(offs) < 5:
        offs.append(i)
        i = data.find(a, i + 1)
    txt = ' '.join('0x%X' % o for o in offs) or '-'
    print("STR|%s|%s|%d|%d|%s" % (a.decode(), b.decode(), data.count(a), data.count(b), txt))
PYSCAN
return 0
fi
local a b
for a in wine_get_version wine_get_host_version wine_get_build_id; do
b="hack_${a#wine_}"
printf 'STR|%s|%s|%s|%s|%s\n' "$a" "$b" \
"$(grep -oa "$a" "$f" 2>/dev/null | wc -l)" \
"$(grep -oa "$b" "$f" 2>/dev/null | wc -l)" "-"
done
}

hw_preview() {
local wineprefix="$1" slug="$2" mode="${3:-patch}"
local exe bkp own mode_bits size state winever
exe="$(find_terminal_exe "$wineprefix")"
if [[ -z "$exe" ]]; then err "terminal64.exe not found under ${wineprefix}/drive_c"; return 1; fi
bkp="${exe}.orig-wine-detect"
own="$(stat -c '%U:%G' "$exe" 2>/dev/null)"
mode_bits="$(stat -c '%a' "$exe" 2>/dev/null)"
size="$(stat -c '%s' "$exe" 2>/dev/null)"
winever="$(wine_version_string 2>/dev/null)"
echo
header
if [[ "$mode" == "restore" ]]; then
title "PREVIEW - RESTORE  ${BOLD}${slug}${NC}"
else
title "PREVIEW - WHAT WILL CHANGE  ${BOLD}${slug}${NC}"
fi
header
echo
echo -e "  ${BOLD}terminal${NC}   ${slug}"
echo -e "  ${BOLD}exe${NC}        ${exe}"
echo -e "  ${BOLD}size${NC}       ${size} bytes   ${BOLD}owner${NC} ${own}   ${BOLD}mode${NC} ${mode_bits}"
echo -e "  ${BOLD}wine here${NC}  ${winever}   ${DIM}(this is what MT5 currently detects)${NC}"
if [[ -f "$bkp" ]]; then
echo -e "  ${BOLD}backup${NC}     ${GREEN}present${NC}  $(stat -c '%s bytes, %y' "$bkp" 2>/dev/null)"
else
echo -e "  ${BOLD}backup${NC}     ${YELLOW}none yet - one will be created${NC}"
fi
state="$(hide_wine_state "$wineprefix")"
echo -e "  ${BOLD}state now${NC}  ${state}"
echo
if [[ "$mode" == "restore" ]]; then
if [[ ! -f "$bkp" ]]; then
err "  No backup to restore from - nothing can be undone here."
header
return 1
fi
echo -e "  ${BOLD}Strings that will come BACK into the binary:${NC}"
echo
printf "    %-24s %-4s %-24s %-4s\n" "FROM (in file now)" "hits" "TO (after restore)" "hits"
printf "    %s\n" "---------------------------------------------------------------------"
while IFS='|' read -r tag from to nfrom nto offs; do
[[ "$tag" == "STR" ]] || continue
[[ "$nto" == "0" ]] && continue
printf "    %-24s ${BOLD}%-4s${NC} ${GREEN}%-24s${NC} %-4s\n" "$to" "$nto" "$from" "$nto"
done < <(hw_string_table "$exe")
echo
echo -e "  ${BOLD}Result${NC}     MT5 will detect Wine again ${DIM}(wine_get_version resolvable)${NC}"
echo -e "  ${BOLD}Restored${NC}   byte-for-byte from ${bkp}, owner ${own} kept"
header
return 0
fi
if ! grep -qa 'wine_get_version' "$exe" 2>/dev/null; then
if grep -qa 'hack_get_version' "$exe" 2>/dev/null; then
ok "  Already patched - no wine_* export names left to rename. Nothing to do."
header
return 2
fi
warn "  This binary has no wine_get_version string at all - nothing to patch."
header
return 2
fi
echo -e "  ${BOLD}Byte-level rename (same length, size never changes):${NC}"
echo
printf "    %-24s %-4s %-24s %s\n" "FROM (found now)" "hits" "TO (after patch)" "offsets"
printf "    %s\n" "---------------------------------------------------------------------------"
while IFS='|' read -r tag from to nfrom nto offs; do
[[ "$tag" == "STR" ]] || continue
if [[ "$nfrom" == "0" ]]; then
printf "    ${DIM}%-24s %-4s %-24s %s${NC}\n" "$from" "0" "$to" "not present - skipped"
else
printf "    %-24s ${BOLD}%-4s${NC} ${GREEN}%-24s${NC} %s\n" "$from" "$nfrom" "$to" "${offs}"
fi
done < <(hw_string_table "$exe")
echo
echo -e "  ${BOLD}Before${NC}     MT5 calls ${RED}wine_get_version${NC} -> resolves -> Journal shows ${RED}${winever}${NC}"
echo -e "  ${BOLD}After${NC}      MT5 calls ${RED}wine_get_version${NC} -> ${GREEN}not found${NC} -> Journal shows ${GREEN}Windows ${WIN10_RELEASE} build ${WIN10_BUILD}${NC}"
echo
echo -e "  ${BOLD}Unchanged${NC}  file size (${size}), owner (${own}), permissions (${mode_bits})"
echo -e "  ${BOLD}Undo${NC}       option 3 in this menu, or: hidewine restore ${slug}"
header
return 0
}

hide_wine_binary_patch() {
local wineprefix="$1" slug="$2"
local exe bkp tmp own mode size_before size_after rc hits
hw_log_init
hlog STEP "=== PATCH START slug=${slug} prefix=${wineprefix} ==="
hlog DBG "wine=$(wine_version_string 2>/dev/null) euid=${EUID} log=${HW_LOG}"

exe="$(find_terminal_exe "$wineprefix")"
if [[ -z "$exe" ]]; then
hlog ERR "terminal64.exe not found under ${wineprefix}/drive_c for ${slug}"
return 1
fi
echo
info "${slug}: ${exe}"
hw_file_facts "$exe" "before"

own="$(stat -c '%U:%G' "$exe" 2>/dev/null)"
mode="$(stat -c '%a' "$exe" 2>/dev/null)"
size_before="$(stat -c '%s' "$exe" 2>/dev/null)"
hlog INFO "owner=${own} mode=${mode} size=${size_before}"

if [[ ! -w "$(dirname "$exe")" ]]; then
hlog WARN "directory not writable: $(dirname "$exe")"
fi

if ! grep -qa 'wine_get_version' "$exe" 2>/dev/null; then
if grep -qa 'hack_get_version' "$exe" 2>/dev/null; then
hlog OK "already patched (hack_get_version present)"
return 0
fi
hlog WARN "no wine_get_version string in this binary - nothing to patch"
return 0
fi
hlog DBG "wine_get_version occurrences: $(grep -oa 'wine_get_version' "$exe" 2>/dev/null | wc -l)"

if exe_is_running "$exe"; then
hlog ERR "this terminal looks like it is running - stop only this one, then retry"
hlog DBG "running pids: $(pgrep -u "${MT5_USER}" -f 'terminal64.exe' 2>/dev/null | tr '\n' ' ')"
return 1
fi

bkp="${exe}.orig-wine-detect"
if [[ -f "$bkp" ]]; then
if grep -qa 'wine_get_version' "$bkp" 2>/dev/null; then
hlog DBG "backup exists and is original (has wine_get_version)"
else
hlog WARN "backup exists but is stale/corrupted (no wine_get_version) - will recreate from exe"
rm -f "$bkp"
fi
fi
if [[ ! -f "$bkp" ]]; then
if ! grep -qa 'wine_get_version' "$exe" 2>/dev/null; then
hlog ERR "exe is patched but no valid backup - cannot re-patch safely; restore with unpatched copy or reinstall"
return 1
fi
if cp -a "$exe" "$bkp" 2>/dev/null; then
hlog OK "backup created from exe: ${bkp}"
else
hlog ERR "backup failed - aborting (disk full? permissions?)"
hlog DBG "df: $(df -h "$(dirname "$exe")" 2>/dev/null | tail -1)"
return 1
fi
else
hlog INFO "backup already valid: ${bkp}"
fi
hw_file_facts "$bkp" "backup"

tmp="$(mktemp "${exe}.hwtmp.XXXXXX" 2>/dev/null)"
if [[ -z "$tmp" ]]; then
hlog ERR "cannot create temp file next to the binary"
return 1
fi

hw_apply_bytes "$bkp" "$tmp" >> "$HW_LOG" 2>&1
rc=$?
hlog DBG "byte-rewrite rc=${rc}"
if (( rc == 90 )); then
hlog ERR "replacement string length mismatch - refusing to resize the binary"
rm -f "$tmp"; return 1
fi
if (( rc != 0 && rc != 91 )); then
hlog ERR "byte rewrite failed (rc=${rc}) - nothing changed"
rm -f "$tmp"; return 1
fi

size_after="$(stat -c '%s' "$tmp" 2>/dev/null)"
hlog DBG "size check: before=${size_before} after=${size_after}"
if [[ "$size_before" != "$size_after" ]]; then
hlog ERR "size changed (${size_before} -> ${size_after}) - aborting, binary untouched"
rm -f "$tmp"; return 1
fi
if grep -qa 'wine_get_version' "$tmp" 2>/dev/null; then
hlog ERR "patched copy still contains wine_get_version - aborting, binary untouched"
rm -f "$tmp"; return 1
fi

if ! hw_write_inplace "$tmp" "$exe"; then
hlog ERR "in-place write failed - restoring from backup"
cat "$bkp" > "$exe" 2>/dev/null
rm -f "$tmp"; return 1
fi
rm -f "$tmp"

chown "$own" "$exe" 2>/dev/null || hlog WARN "chown ${own} failed"
chmod "$mode" "$exe" 2>/dev/null || hlog WARN "chmod ${mode} failed"
hw_file_facts "$exe" "after"

if grep -qa 'wine_get_version' "$exe" 2>/dev/null; then
hlog ERR "patch did not stick - restoring backup"
cat "$bkp" > "$exe" 2>/dev/null
chown "$own" "$exe" 2>/dev/null; chmod "$mode" "$exe" 2>/dev/null
return 1
fi
if [[ "$(stat -c '%U:%G' "$exe" 2>/dev/null)" != "$own" ]]; then
hlog ERR "ownership drifted to $(stat -c '%U:%G' "$exe" 2>/dev/null) - the terminal will not start; fixing"
chown "$own" "$exe" 2>/dev/null
fi
hlog OK "patched - MT5 can no longer resolve wine_get_version"
hlog INFO "size/owner/mode preserved: $(stat -c '%s bytes %U:%G %a' "$exe" 2>/dev/null)"
hlog STEP "=== PATCH DONE slug=${slug} ==="
return 0
}

hide_wine_restore_one() {
local wineprefix="$1" slug="$2"
local exe bkp own mode
hw_log_init
hlog STEP "=== RESTORE START slug=${slug} ==="
exe="$(find_terminal_exe "$wineprefix")"
if [[ -z "$exe" ]]; then hlog ERR "terminal64.exe not found for ${slug}"; return 1; fi
bkp="${exe}.orig-wine-detect"
echo
info "${slug}: ${exe}"
if [[ ! -f "$bkp" ]]; then
hlog ERR "no backup found (${bkp}) - cannot restore; reinstall the terminal instead"
return 1
fi
if exe_is_running "$exe"; then
hlog ERR "terminal is running - stop it first"
return 1
fi
own="$(stat -c '%U:%G' "$bkp" 2>/dev/null)"; own="${own:-${MT5_USER}:${MT5_USER}}"
mode="$(stat -c '%a' "$bkp" 2>/dev/null)"; mode="${mode:-755}"
hw_file_facts "$exe" "before-restore"
hw_file_facts "$bkp" "backup"
if ! cat "$bkp" > "$exe" 2>/dev/null; then
hlog ERR "restore write failed"
return 1
fi
chown "$own" "$exe" 2>/dev/null || hlog WARN "chown ${own} failed"
chmod "$mode" "$exe" 2>/dev/null || hlog WARN "chmod ${mode} failed"
hw_file_facts "$exe" "after-restore"
if grep -qa 'wine_get_version' "$exe" 2>/dev/null; then
hlog OK "original terminal64.exe restored (${own} ${mode})"
hlog STEP "=== RESTORE DONE slug=${slug} ==="
return 0
fi
hlog WARN "restored, but wine_get_version is still absent - backup may itself be patched"
return 0
}

hide_wine_restore_all() {
local slug exe wineprefix termpath n_ok=0 n_fail=0
if [[ ! -s "$TERMINALS_FILE" ]]; then err "No terminals registered."; return 1; fi
while IFS='|' read -r slug exe wineprefix termpath; do
[[ -z "${slug:-}" || -z "${wineprefix:-}" ]] && continue
if hide_wine_restore_one "$wineprefix" "$slug"; then ((n_ok++)); else ((n_fail++)); fi
done < "$TERMINALS_FILE"
echo; header
ok "Restored ${n_ok}, failed ${n_fail}."
header
}

hide_wine_diagnose() {
local wineprefix="$1" slug="$2"
local exe tlog rc pid_alive out
hw_log_init
exe="$(find_terminal_exe "$wineprefix")"
if [[ -z "$exe" ]]; then hlog ERR "terminal64.exe not found for ${slug}"; return 1; fi
tlog="$(hw_terminal_log_path "$slug")"
echo; header
title "DIAGNOSE ${slug}"
header
hlog STEP "=== DIAGNOSE START slug=${slug} ==="
hlog INFO "exe: ${exe}"
hlog INFO "state: $(hide_wine_state "$wineprefix")"
hw_file_facts "$exe" "exe"
hw_file_facts "${exe}.orig-wine-detect" "backup"
hlog DBG "wine: $(wine_version_string 2>/dev/null)"
hlog DBG "prefix owner: $(stat -c '%U:%G' "$wineprefix" 2>/dev/null)"
hlog DBG "mt5user can read exe: $(runuser -u "${MT5_USER}" -- test -r "$exe" 2>/dev/null && echo yes || echo NO)"
hlog DBG "mt5user can exec exe: $(runuser -u "${MT5_USER}" -- test -x "$exe" 2>/dev/null && echo yes || echo NO)"

if exe_is_running "$exe"; then
hlog WARN "terminal is currently running - stop it for a clean diagnose"
fi
ensure_display >/dev/null 2>&1 || hlog WARN "no display on :1 - launch test may fail"

hlog STEP "launching in foreground for ${HW_DIAG_SECS}s, capturing wine output..."
echo "----- wine stdout/stderr begin -----" >> "$HW_LOG"
timeout "${HW_DIAG_SECS}" runuser -u "${MT5_USER}" -- bash -lc "export DISPLAY=:1 WINEDEBUG='err+all,warn+module' WINEDLLOVERRIDES='winemenubuilder.exe=d' WINEPREFIX='${wineprefix}'; wine '${exe}'" >> "$HW_LOG" 2>&1
rc=$?
echo "----- wine stdout/stderr end (rc=${rc}) -----" >> "$HW_LOG"
hlog DBG "launch exit code: ${rc}"
if (( rc == 124 )); then
hlog OK "still alive after ${HW_DIAG_SECS}s - the terminal does start (rc=124 = timeout, that is good)"
else
hlog ERR "terminal exited by itself with code ${rc} - this is the failure"
fi

echo
title "last 40 lines of the wine output:"
tail -n 40 "$HW_LOG" 2>/dev/null | sed -n '/wine stdout/,$p' | head -60
if [[ -f "$tlog" ]]; then
echo
title "last 25 lines of ${tlog}:"
tail -n 25 "$tlog" 2>/dev/null
else
hlog WARN "no launcher log at ${tlog} yet"
fi
echo
info "full log: ${HW_LOG}"
hlog STEP "=== DIAGNOSE DONE slug=${slug} ==="
}

hide_wine_show_log() {
hw_log_init
echo; header
title "HIDE-WINE LOG  ${DIM}${HW_LOG}${NC}"
header
if [[ ! -s "$HW_LOG" ]]; then
warn "Log is empty - nothing has run yet."
return 0
fi
tail -n "${1:-120}" "$HW_LOG"
echo
header
info "full file: ${HW_LOG}  (live: tail -f ${HW_LOG})"
}

hide_wine_confirm() {
warn "This edits terminal64.exe in place (a .orig-wine-detect backup is kept)."
warn "Stop the affected terminal(s) first."
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

hide_wine_restore_slug() {
local slug="$1" wineprefix
wineprefix=$(awk -F'|' -v s="$slug" '$1==s{print $3; exit}' "$TERMINALS_FILE" 2>/dev/null)
if [[ -z "$wineprefix" ]]; then err "Terminal not found: $slug"; return 1; fi
hide_wine_restore_one "$wineprefix" "$slug"
}

hide_wine_diagnose_slug() {
local slug="$1" wineprefix
wineprefix=$(awk -F'|' -v s="$slug" '$1==s{print $3; exit}' "$TERMINALS_FILE" 2>/dev/null)
if [[ -z "$wineprefix" ]]; then err "Terminal not found: $slug"; return 1; fi
hide_wine_diagnose "$wineprefix" "$slug"
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
warn "${n_ok} done, ${n_fail} failed - see ${HW_LOG}"
fi
header
}

hw_pick_terminal() {
local i=1 slug exe wineprefix termpath idx
HW_PICK_SLUG=""; HW_PICK_PREFIX=""
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
IFS='|' read -r HW_PICK_SLUG HW_PICK_PREFIX <<< "${HW_LIST[$((idx-1))]}"
echo
info "Selected: ${BOLD}${HW_PICK_SLUG}${NC}"
return 0
}

hide_wine_binary_patch_pick() {
hw_pick_terminal || return 1
hw_preview "$HW_PICK_PREFIX" "$HW_PICK_SLUG" patch
case $? in
2) return 0 ;;
1) return 1 ;;
esac
hide_wine_confirm || return 1
if hide_wine_binary_patch "$HW_PICK_PREFIX" "$HW_PICK_SLUG"; then
echo
ok "Restart ${HW_PICK_SLUG} only, then check its Journal tab."
info "If it does not start: option 4 (diagnose) shows exactly where it dies."
fi
}

hide_wine_restore_pick() {
hw_pick_terminal || return 1
hw_preview "$HW_PICK_PREFIX" "$HW_PICK_SLUG" restore || return 1
local ans=""
if [[ -t 0 ]]; then
read -rp "$(echo -e "Type ${BOLD}yes${NC} to restore: ")" ans || ans=""
[[ "${ans,,}" == "yes" ]] || { warn "Cancelled - no changes made."; return 1; }
fi
hide_wine_restore_one "$HW_PICK_PREFIX" "$HW_PICK_SLUG"
}

hide_wine_diagnose_pick() {
hw_pick_terminal || return 1
hide_wine_diagnose "$HW_PICK_PREFIX" "$HW_PICK_SLUG"
}

hide_wine_menu() {
if [[ ! -s "$TERMINALS_FILE" ]]; then
err "No terminals registered."
return 1
fi
hw_log_init
local CH
echo
header
title "HIDE WINE FROM MT5 - terminal64.exe binary patch"
header
echo -e "  wine: ${BOLD}$(wine_version_string)${NC}"
echo -e "  log:  ${DIM}${HW_LOG}${NC}"
echo
echo -e "  ${BOLD}1)${NC} Patch all terminals"
echo -e "  ${BOLD}2)${NC} Patch one terminal from the list"
echo -e "  ${BOLD}3)${NC} Restore original terminal64.exe ${DIM}(undo the patch)${NC}"
echo -e "  ${BOLD}4)${NC} Diagnose a terminal ${DIM}(launch it, capture the full wine log)${NC}"
echo -e "  ${BOLD}5)${NC} Show log ${DIM}(last 120 lines)${NC}"
echo -e "  ${BOLD}6)${NC} Toggle verbose debug  ${DIM}[currently: ${HW_DEBUG:-0}]${NC}"
echo -e "  ${BOLD}0)${NC} Cancel"
echo
read -rp "Choice [${BOLD}1${NC}]: " CH || CH=""
CH="${CH:-1}"
case "${CH// /}" in
1) echo; hide_wine_confirm || return 1; HW_SKIP_CONFIRM=1 hide_wine_binary_patch_all ;;
2) hide_wine_binary_patch_pick ;;
3) hide_wine_restore_pick ;;
4) hide_wine_diagnose_pick ;;
5) hide_wine_show_log 120 ;;
6)
if [[ "${HW_DEBUG:-0}" == "1" ]]; then HW_DEBUG=0; info "Verbose debug OFF"; else HW_DEBUG=1; info "Verbose debug ON"; fi
export HW_DEBUG
;;
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
echo -e "  ${BOLD}4)${NC} Apply compliance to SPECIFIC terminal"
echo -e "  ${BOLD}5)${NC} Change Windows version/build profile"
echo -e "  ${BOLD}H)${NC} Hide Wine from MT5 (patch terminal64.exe)  ${DIM}(patch / restore / diagnose + log)${NC}"
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
h|H) hide_wine_menu; read -rp "Press Enter to continue..." _ ;;
4)
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
5) choose_profile; read -rp "Press Enter to continue..." _ ;;
0) exit 0 ;;
*) warn "Invalid option."; sleep 1 ;;
esac
done
}

usage() {
echo "Usage: wine-compliance.sh [menu|apply|test|revert|version|hidewine] [slug]"
echo
echo "Commands:"
echo "  menu              - Interactive menu (default)"
echo "  apply [slug]      - Apply compliance to all or specific terminal"
echo "  test              - Test compliance on all terminals"
echo "  revert [slug]     - Revert compliance from all or specific terminal"
echo "  version [n|build] - Pick a Windows profile (preset number or build, e.g. 19045)"
echo "  hidewine [slug]   - Patch terminal64.exe (no slug = menu: all or pick one)"
echo "  hidewine all      - Patch every terminal"
echo "  hidewine restore [slug|all] - Undo the patch from the .orig-wine-detect backup"
echo "  hidewine diagnose <slug>    - Launch the terminal and capture the full wine log"
echo "  hidewine log [n]  - Show the hide-wine log (default 120 lines)"
echo
echo "Hide-wine log: /var/log/heysolo-hidewine.log   (HW_DEBUG=1 for verbose output)"
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
test_compliance_all
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
hidewine)
case "${2:-}" in
"") hide_wine_menu ;;
all) HW_SKIP_CONFIRM=1 hide_wine_binary_patch_all ;;
restore)
if [[ -n "${3:-}" && "${3}" != "all" ]]; then hide_wine_restore_slug "$3"; else hide_wine_restore_all; fi
;;
diagnose|diag)
if [[ -z "${3:-}" ]]; then err "Usage: hidewine diagnose <slug>"; exit 1; fi
hide_wine_diagnose_slug "$3"
;;
log|logs) hide_wine_show_log "${3:-120}" ;;
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