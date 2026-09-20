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

host_kernel_string() {
uname -sr 2>/dev/null
}

wine_full_string() {
local v k
v="$(wine_version_string 2>/dev/null)"
v="${v#wine-}"
v="${v%% *}"
k="$(host_kernel_string)"
printf 'Wine %s %s' "${v:-unknown}" "${k:-unknown}"
}

hw_latest_journal() {
find "${1}/drive_c" -maxdepth 10 -type f -name '*.log' -path '*/[Ll]ogs/*' -not -path '*/MQL5/*' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-
}

hw_journal_line() {
local f="$1"
[[ -n "$f" && -r "$f" ]] || return 1
tr -d '\000\r' < "$f" | grep -a -i 'build' | grep -a -i -E 'windows|wine' | tail -n 1
}

hw_journal_verify() {
local wineprefix="$1" slug="$2" exe f line
exe="$(find_terminal_exe "$wineprefix")"
f="$(hw_latest_journal "$wineprefix")"
echo
title "JOURNAL CHECK  ${BOLD}${slug}${NC}"
if [[ -z "$f" ]]; then
warn "  no Journal file found for ${slug} - start the terminal once, then check again."
return 2
fi
if [[ -n "$exe" && ! "$f" -nt "$exe" ]]; then
warn "  newest Journal is older than the patch - restart ${slug}, wait a few seconds, then check again."
return 2
fi
line="$(hw_journal_line "$f")"
if [[ -z "$line" ]]; then
warn "  no OS line in the Journal yet - wait until the terminal has fully started, then check again."
return 2
fi
echo -e "  ${BOLD}file${NC}   ${f}"
echo -e "  ${BOLD}line${NC}   ${line}"
if grep -qiE 'wine|linux' <<< "$line"; then
err "  Journal still reveals Wine / Linux - patch incomplete or the terminal was not restarted."
return 1
fi
ok "  Journal is clean - no Wine / Linux in the OS line."
return 0
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
warn "MT5 will still print \"on Wine ... Linux ...\"."
info "To drop that suffix: install wine-staging, or run the terminal64.exe binary patch (option H)."
fi
local bps
bps="$(bp_state)"
if [[ "$bps" == "ok" ]]; then
ok "Wine's ${WIN10_WINVER} version table already reports ${WIN10_BUILD} - MT5 will show that build."
elif [[ "$bps" == build:* ]]; then
warn "Wine's ${WIN10_WINVER} version table reports ${bps#build:}. MT5 reads THAT number, not the registry."
if [[ "${COMPLIANCE_AUTO_BUILDPATCH:-1}" == "1" ]]; then
info "Applying will also patch that table to ${WIN10_BUILD} automatically (backup kept, undo: buildpatch restore)."
else
info "Auto patch is off (COMPLIANCE_AUTO_BUILDPATCH=0). Use menu option B or: wine-compliance.sh buildpatch"
fi
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

wreg_get() {
local wineprefix="$1" key="$2" val="$3"
as_mt5 "WINEPREFIX='${wineprefix}' wine reg query '${key}' /v ${val}" 2>/dev/null | tr -d '\r' | awk -v v="$val" '$1==v { sub(/^[[:space:]]*[^[:space:]]+[[:space:]]+REG_[A-Z_]+[[:space:]]+/, ""); print; exit }'
}

effective_build() {
local wineprefix="$1" winver="$2" out
cat > "/tmp/wine-effver-$$.reg" <<EOF
Windows Registry Editor Version 5.00
[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\cmd.exe]
"Version"="${winver}"
EOF
as_mt5 "WINEPREFIX='${wineprefix}' wine regedit /S '/tmp/wine-effver-$$.reg'" >/dev/null 2>&1
out=$(as_mt5 "WINEPREFIX='${wineprefix}' wine cmd /c ver" 2>/dev/null | tr -d '\r' | grep -oP '10\.0\.\K[0-9]+' | head -1)
cat > "/tmp/wine-effver-$$.reg" <<EOF
Windows Registry Editor Version 5.00
[-HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\cmd.exe]
EOF
as_mt5 "WINEPREFIX='${wineprefix}' wine regedit /S '/tmp/wine-effver-$$.reg'" >/dev/null 2>&1
rm -f "/tmp/wine-effver-$$.reg"
echo "$out"
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

step 8 $total "Verifying the import (registry + the build MT5 will actually see)" "$t0"
local win_build win_prod win_appver eff_build reg_ok=1
win_build=$(wreg_get "$wineprefix" 'HKLM\Software\Microsoft\Windows NT\CurrentVersion' CurrentBuild)
win_prod=$(wreg_get "$wineprefix" 'HKLM\Software\Microsoft\Windows NT\CurrentVersion' ProductName)
win_appver=$(wreg_get "$wineprefix" 'HKCU\Software\Wine\AppDefaults\terminal64.exe' Version)
[[ "$win_build" == "$WIN10_BUILD" ]] || reg_ok=0
[[ "$win_prod" == "$WIN10_PRODUCT" ]] || reg_ok=0
[[ "${win_appver,,}" == "${WIN10_WINVER,,}" ]] || reg_ok=0
eff_build=$(effective_build "$wineprefix" "$WIN10_WINVER")
if [[ ${reg_ok} -eq 1 && "$eff_build" =~ ^[0-9]+$ && "$eff_build" != "$WIN10_BUILD" && "${COMPLIANCE_AUTO_BUILDPATCH:-1}" == "1" && "${BP_AUTO_TRIED:-}" != "${WIN10_WINVER}:${WIN10_BUILD}" ]]; then
info "    Wine's ${WIN10_WINVER} table reports ${eff_build} but the profile wants ${WIN10_BUILD} - patching Wine's version table now..."
BP_ASSUME_YES=1 buildpatch_apply
eff_build=$(effective_build "$wineprefix" "$WIN10_WINVER")
info "    MT5 sees : build ${eff_build:-unknown}  (after build patch)"
[[ "$eff_build" == "$WIN10_BUILD" ]] || BP_AUTO_TRIED="${WIN10_WINVER}:${WIN10_BUILD}"
fi

local total_time=$(( $(date +%s) - t0 ))
info "    registry : CurrentBuild=${win_build:-NOT SET}  ProductName=${win_prod:-NOT SET}  terminal64.exe Version=${win_appver:-NOT SET}"
info "    MT5 sees : build ${eff_build:-unknown}  (profile wants ${WIN10_BUILD})"
if [[ ${import1_ok} -eq 1 && ${import2_ok} -eq 1 && ${reg_ok} -eq 1 ]]; then
mkdir -p "$(dirname "$COMPLIANCE_STATE_FILE")"
grep -v "^${slug}|" "$COMPLIANCE_STATE_FILE" > "${COMPLIANCE_STATE_FILE}.tmp" 2>/dev/null || true
echo "${slug}|${wineprefix}|$(date +%s)" >> "${COMPLIANCE_STATE_FILE}.tmp"
mv "${COMPLIANCE_STATE_FILE}.tmp" "$COMPLIANCE_STATE_FILE" 2>/dev/null || true
if [[ "$eff_build" == "$WIN10_BUILD" ]]; then
ok "Compliance applied to ${slug} (verified end-to-end: build ${eff_build}, took ${total_time}s)"
info "    Restart this terminal so MT5 reloads the version:  sudo heysolo  ->  R1, R2, ..."
else
if [[ -z "$eff_build" ]]; then
warn "Registry applied to ${slug}, but the build MT5 will see could not be determined (took ${total_time}s)"
else
warn "Registry applied to ${slug}, but Wine itself reports build ${eff_build} for ${WIN10_WINVER} - MT5 will show that, not ${WIN10_BUILD} (took ${total_time}s)"
fi
info "    See what the build patch found:  sudo bash /opt/heysolo/scripts/win/wine-compliance.sh buildpatch status"
fi
log "Compliance applied to ${slug} (${wineprefix}) registry build=${win_build} product=${win_prod} appver=${win_appver} effective=${eff_build:-unknown} took=${total_time}s"
return 0
else
err "Compliance import failed for ${slug} after ${total_time}s (regedit ok: ${import1_ok}/${import2_ok}; registry build '${win_build:-NOT SET}' expected ${WIN10_BUILD}; product '${win_prod:-NOT SET}' expected '${WIN10_PRODUCT}'; terminal64.exe Version '${win_appver:-NOT SET}' expected ${WIN10_WINVER})."
log "Compliance apply FAILED for ${slug} (${wineprefix}) - import1=${import1_ok} import2=${import2_ok} build=${win_build:-NOT SET} product=${win_prod:-NOT SET} appver=${win_appver:-NOT SET} took=${total_time}s"
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
win_version=$(as_mt5 "WINEPREFIX='${wineprefix}' wine reg query \"HKLM\Software\Microsoft\Windows NT\CurrentVersion\" /v CurrentBuild" 2>/dev/null | grep -oP '\d+' | tail -1)
if [[ "$win_version" == "$WIN10_BUILD" ]]; then
ok "Windows build: ${win_version} (expected: ${WIN10_BUILD})"
else
err "Windows build: ${win_version:-NOT SET} (expected: ${WIN10_BUILD})"
((issues++))
fi

info "Test 2: Product name..."
local product_name
product_name=$(as_mt5 "WINEPREFIX='${wineprefix}' wine reg query \"HKLM\Software\Microsoft\Windows NT\CurrentVersion\" /v ProductName" 2>/dev/null | sed -n 's/.*REG_SZ[[:space:]]*//p' | tr -d '\r')
if [[ "$product_name" == *"$WIN10_PRODUCT"* ]]; then
ok "Product name: ${product_name}"
else
err "Product name: ${product_name:-NOT SET} (expected: ${WIN10_PRODUCT})"
((issues++))
fi

info "Test 3: Non-standard registry keys..."
local wine_keys
wine_keys=$(as_mt5 "WINEPREFIX='${wineprefix}' wine reg query \"HKLM\Software\Wine\"" 2>/dev/null)
if [[ -z "$wine_keys" ]]; then
ok "No non-standard registry keys found"
else
err "Non-standard registry keys still present"
((issues++))
fi

info "Test 4: DLL overrides for terminal64.exe..."
local dll_override
dll_override=$(as_mt5 "WINEPREFIX='${wineprefix}' wine reg query \"HKCU\Software\Wine\AppDefaults\terminal64.exe\" /v Version" 2>/dev/null | sed -n 's/.*REG_SZ[[:space:]]*//p' | tr -d '\r')
if [[ "$dll_override" == "$WIN10_WINVER" ]]; then
ok "terminal64.exe version override: ${dll_override}"
else
err "terminal64.exe version override: ${dll_override:-NOT SET} (expected: ${WIN10_WINVER})"
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

info "Test 7: Build MT5 will actually see (Wine version table)..."
local eff_build
eff_build=$(effective_build "$wineprefix" "$WIN10_WINVER")
if [[ "$eff_build" == "$WIN10_BUILD" ]]; then
ok "Effective build: ${eff_build} (expected: ${WIN10_BUILD})"
else
err "Effective build: ${eff_build:-unknown} (expected: ${WIN10_BUILD}) - run buildpatch"
((issues++))
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
leftover=$(as_mt5 "WINEPREFIX='${wineprefix}' wine reg query \"HKCU\Software\Wine\AppDefaults\terminal64.exe\" /v Version" 2>/dev/null | sed -n 's/.*REG_SZ[[:space:]]*//p' | tr -d '\r')

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
local exe bkp own mode_bits size state winever wfull kern vh hh
exe="$(find_terminal_exe "$wineprefix")"
if [[ -z "$exe" ]]; then err "terminal64.exe not found under ${wineprefix}/drive_c"; return 1; fi
bkp="${exe}.orig-wine-detect"
own="$(stat -c '%U:%G' "$exe" 2>/dev/null)"
mode_bits="$(stat -c '%a' "$exe" 2>/dev/null)"
size="$(stat -c '%s' "$exe" 2>/dev/null)"
winever="$(wine_version_string 2>/dev/null)"
wfull="$(wine_full_string)"
kern="$(host_kernel_string)"
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
echo -e "  ${BOLD}wine here${NC}  ${winever}   ${DIM}(wine --version only - not the full text)${NC}"
echo -e "  ${BOLD}MT5 sees${NC}   ${YELLOW}on ${wfull}${NC}   ${DIM}(full text MT5 prints in the Journal)${NC}"
echo -e "  ${BOLD}made of${NC}    wine_get_version -> ${winever#wine-}    wine_get_host_version -> ${kern}"
echo -e "  ${BOLD}profile${NC}    $(current_profile_line)"
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
printf "    %-24s %-4s %-24s %-13s %s\n" "FROM (found now)" "hits" "TO (after patch)" "hides" "offsets"
printf "    %s\n" "---------------------------------------------------------------------------------------"
vh=0; hh=0
while IFS='|' read -r tag from to nfrom nto offs; do
[[ "$tag" == "STR" ]] || continue
local part
case "$from" in
wine_get_version)      part="Wine part"; vh="$nfrom" ;;
wine_get_host_version) part="Linux part"; hh="$nfrom" ;;
*)                     part="build id" ;;
esac
if [[ "$nfrom" == "0" ]]; then
printf "    ${DIM}%-24s %-4s %-24s %-13s %s${NC}\n" "$from" "0" "$to" "-" "not present - skipped"
else
printf "    %-24s ${BOLD}%-4s${NC} ${GREEN}%-24s${NC} %-13s %s\n" "$from" "$nfrom" "$to" "${part:0:13}" "${offs}"
fi
done < <(hw_string_table "$exe")
echo
echo -e "  ${BOLD}Before${NC}     Journal ends with: ${RED}on ${wfull}${NC}"
if (( vh > 0 && hh > 0 )); then
echo -e "  ${BOLD}After${NC}      MT5 cannot resolve either function -> ${GREEN}no 'Wine ${winever#wine-}' and no '${kern}'${NC}, Journal shows Windows build ${GREEN}${WIN10_BUILD}${NC} (${WIN10_RELEASE})"
else
if (( vh == 0 )); then echo -e "  ${BOLD}After${NC}      ${YELLOW}wine_get_version not in this binary - the 'Wine ${winever#wine-}' part will NOT be hidden${NC}"; fi
if (( hh == 0 )); then echo -e "  ${BOLD}After${NC}      ${YELLOW}wine_get_host_version not in this binary - the '${kern}' part will NOT be hidden${NC}"; fi
fi
echo -e "  ${BOLD}Verify${NC}     restart the terminal, then option 7 (or: hidewine verify ${slug}) reads the real Journal line"
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
if grep -qaE 'wine_get_(host_version|build_id)' "$exe" 2>/dev/null; then
hlog WARN "wine_get_host_version / wine_get_build_id still present - the Linux part may still show"
else
hlog OK "wine_get_host_version and wine_get_build_id also gone - Wine and Linux parts are both hidden"
fi
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

hide_wine_verify_slug() {
local slug="$1" wineprefix
wineprefix=$(awk -F'|' -v s="$slug" '$1==s{print $3; exit}' "$TERMINALS_FILE" 2>/dev/null)
if [[ -z "$wineprefix" ]]; then err "Terminal not found: $slug"; return 1; fi
hw_journal_verify "$wineprefix" "$slug"
}

hide_wine_verify_all() {
local slug exe wineprefix termpath
while IFS='|' read -r slug exe wineprefix termpath; do
[[ -z "${slug:-}" || -z "${wineprefix:-}" ]] && continue
hw_journal_verify "$wineprefix" "$slug"
done < "$TERMINALS_FILE"
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
ok "Done on ${n_ok} terminal(s). Restart them, then run: hidewine verify"
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
info "After restarting it, option 7 checks that the Journal really shows no Wine / Linux."
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

hide_wine_verify_pick() {
hw_pick_terminal || return 1
hw_journal_verify "$HW_PICK_PREFIX" "$HW_PICK_SLUG"
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
echo -e "  wine: ${BOLD}$(wine_version_string)${NC}   ${DIM}(MT5 sees: on $(wine_full_string))${NC}"
echo -e "  log:  ${DIM}${HW_LOG}${NC}"
echo
echo -e "  ${BOLD}1)${NC} Patch all terminals"
echo -e "  ${BOLD}2)${NC} Patch one terminal from the list"
echo -e "  ${BOLD}3)${NC} Restore original terminal64.exe ${DIM}(undo the patch)${NC}"
echo -e "  ${BOLD}4)${NC} Diagnose a terminal ${DIM}(launch it, capture the full wine log)${NC}"
echo -e "  ${BOLD}5)${NC} Show log ${DIM}(last 120 lines)${NC}"
echo -e "  ${BOLD}6)${NC} Toggle verbose debug  ${DIM}[currently: ${HW_DEBUG:-0}]${NC}"
echo -e "  ${BOLD}7)${NC} Verify Journal after restart ${DIM}(reads the real OS line MT5 wrote)${NC}"
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
7) hide_wine_verify_pick ;;
6)
if [[ "${HW_DEBUG:-0}" == "1" ]]; then HW_DEBUG=0; info "Verbose debug OFF"; else HW_DEBUG=1; info "Verbose debug ON"; fi
export HW_DEBUG
;;
0) info "Cancelled." ;;
*) err "Invalid selection." ;;
esac
}

bp_py() {
command -v python3 >/dev/null 2>&1 || return 127
python3 - "$@" <<'PY'
import re, struct, sys
mode, path, winver, want = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
out = sys.argv[5] if len(sys.argv) > 5 else None
data = open(path, 'rb').read()
rx = re.compile(rb'(?=\x0a\x00\x00\x00\x00\x00\x00\x00(..)\x00\x00\x02\x00\x00\x00)', re.S)
hits = []
for m in rx.finditer(data):
    b = struct.unpack('<H', m.group(1))[0]
    if 10000 <= b <= 40000:
        hits.append((m.start() + 8, b))
want11 = (winver == 'win11')
cls = [h for h in hits if (h[1] >= 22000) == want11]
for off, b in hits:
    print("HIT|0x%X|%d|%s" % (off, b, 'win11' if b >= 22000 else 'win10'))
if mode == 'scan':
    print("CLASS|%d|%s" % (len(cls), cls[0][1] if len(cls) == 1 else '-'))
    sys.exit(0 if len(cls) == 1 else 2)
if len(cls) != 1:
    sys.exit(2)
if not (10000 <= want <= 40000) or (want >= 22000) != want11:
    sys.exit(3)
off, cur = cls[0]
if cur == want:
    print("SAME|%d" % cur)
    sys.exit(10)
buf = bytearray(data)
buf[off:off + 2] = struct.pack('<H', want)
open(out, 'wb').write(bytes(buf))
print("PATCH|0x%X|%d|%d" % (off, cur, want))
sys.exit(0)
PY
}

bp_find_ntdll() {
local w root
w="$(as_mt5 "command -v wine" 2>/dev/null | tr -d '\r' | head -1)"
[[ -z "$w" ]] && w="$(command -v wine 2>/dev/null)"
[[ -n "$w" ]] && w="$(readlink -f "$w" 2>/dev/null)"
if [[ -z "${WINE_ROOT:-}" && -z "$w" ]]; then return 0; fi
root="${WINE_ROOT:-$(dirname "$(dirname "$w")")}"
find "$root" -maxdepth 7 -type f -name ntdll.dll -path '*-windows/*' 2>/dev/null | sort -u
}

bp_state() {
local files f out cls
files="$(bp_find_ntdll)"
f="$(printf '%s\n' "$files" | grep -m1 'x86_64-windows')"
[[ -z "$f" ]] && f="$(printf '%s\n' "$files" | head -1)"
if [[ -z "$f" ]]; then echo unknown; return 0; fi
out="$(bp_py scan "$f" "$WIN10_WINVER" "$WIN10_BUILD" 2>/dev/null)"
cls="$(printf '%s\n' "$out" | awk -F'|' '$1=="CLASS" && $2==1 {print $3}')"
if [[ -z "$cls" ]]; then echo unknown
elif [[ "$cls" == "$WIN10_BUILD" ]]; then echo ok
else echo "build:${cls}"; fi
}

bp_backup_stale() {
local f="$1" bkp="$2"
[[ "$(stat -c %s "$bkp" 2>/dev/null)" != "$(stat -c %s "$f" 2>/dev/null)" ]] && return 0
(( $(cmp -l "$bkp" "$f" 2>/dev/null | wc -l) > 8 )) && return 0
return 1
}

buildpatch_status() {
local files f out
files="$(bp_find_ntdll)"
echo
header
title "WINE WINDOWS BUILD TABLE"
header
echo -e "  wine:    ${BOLD}$(wine_version_string)${NC}"
echo -e "  profile: ${BOLD}$(current_profile_line)${NC}  ${DIM}(${WIN10_WINVER} entry -> ${WIN10_BUILD})${NC}"
if [[ -z "$files" ]]; then
warn "Could not find Wine's ntdll.dll (set WINE_ROOT=/path/to/wine to point at it)."
return 1
fi
while IFS= read -r f; do
[[ -z "$f" ]] && continue
out="$(bp_py scan "$f" "$WIN10_WINVER" "$WIN10_BUILD" 2>&1)"
echo -e "  ${BOLD}${f}${NC}"
printf '%s\n' "$out" | awk -F'|' '$1=="HIT"{printf "    %s entry: build %s  (offset %s)\n",$4,$3,$2}'
if [[ -f "${f}.orig-build" ]]; then echo -e "    ${DIM}backup: ${f}.orig-build${NC}"; else echo -e "    ${DIM}no backup - never patched${NC}"; fi
done <<< "$files"
header
}

buildpatch_apply() {
if ! command -v python3 >/dev/null 2>&1; then err "python3 is required for the build patch."; return 1; fi
local files f out tmp bkp rc ans="" done_n=0 fail_n=0 same_n=0
files="$(bp_find_ntdll)"
if [[ -z "$files" ]]; then
err "Could not find Wine's ntdll.dll. Set WINE_ROOT=/path/to/wine (the folder holding bin/ and lib/) and retry."
return 1
fi
echo
header
title "PATCH WINE'S WINDOWS BUILD TABLE"
header
echo -e "  profile: ${BOLD}$(current_profile_line)${NC}"
echo -e "  Wine's built-in ${BOLD}${WIN10_WINVER}${NC} entry will report build ${BOLD}${WIN10_BUILD}${NC} to every program running as ${WIN10_WINVER}."
echo -e "  ${DIM}A backup is kept next to each file as *.orig-build - undo with: wine-compliance.sh buildpatch restore${NC}"
echo -e "  ${DIM}A Wine package upgrade replaces these files, so re-run this after upgrading Wine.${NC}"
while IFS= read -r f; do [[ -n "$f" ]] && echo "    $f"; done <<< "$files"
if [[ -t 0 && "${BP_ASSUME_YES:-0}" != "1" ]]; then
echo
read -rp "$(echo -e "Press ${BOLD}Enter${NC} to patch, or type ${BOLD}n${NC} to cancel: ")" ans || ans=""
if [[ "${ans,,}" == "n" || "${ans,,}" == "no" ]]; then warn "Cancelled - nothing changed."; return 1; fi
fi
echo
while IFS= read -r f; do
[[ -z "$f" ]] && continue
bkp="${f}.orig-build"
if [[ -f "$bkp" ]] && bp_backup_stale "$f" "$bkp"; then
info "  Wine was updated since the last backup - refreshing the backup of ${f}"
rm -f "$bkp"
fi
if [[ ! -f "$bkp" ]]; then
if ! cp -a "$f" "$bkp" 2>/dev/null; then err "  backup failed, skipping ${f}"; ((fail_n++)); continue; fi
fi
tmp="$(mktemp "${f}.bptmp.XXXXXX" 2>/dev/null)"
if [[ -z "$tmp" ]]; then err "  cannot write next to ${f}"; ((fail_n++)); continue; fi
out="$(bp_py patch "$f" "$WIN10_WINVER" "$WIN10_BUILD" "$tmp" 2>&1)"; rc=$?
case "$rc" in
0)
chown --reference="$f" "$tmp" 2>/dev/null
chmod --reference="$f" "$tmp" 2>/dev/null
if [[ "$(stat -c %s "$tmp")" != "$(stat -c %s "$f")" ]]; then
err "  size changed - aborting for ${f}"; rm -f "$tmp"; ((fail_n++)); continue
fi
if ! mv -f "$tmp" "$f" 2>/dev/null; then err "  could not replace ${f}"; rm -f "$tmp"; ((fail_n++)); continue; fi
if [[ "$(bp_py scan "$f" "$WIN10_WINVER" "$WIN10_BUILD" 2>/dev/null | awk -F'|' '$1=="CLASS" && $2==1 {print $3}')" == "$WIN10_BUILD" ]]; then
ok "  patched ${f}  ($(printf '%s' "$out" | awk -F'|' '$1=="PATCH"{print $3" -> "$4}'))"
((done_n++))
else
err "  patch did not stick - restoring ${f}"
cp -a "$bkp" "$f" 2>/dev/null
((fail_n++))
fi
;;
10) rm -f "$tmp"; info "  already ${WIN10_BUILD}: ${f}"; ((same_n++)) ;;
2) rm -f "$tmp"; warn "  ntdll layout not recognised (need exactly one ${WIN10_WINVER} entry) - left untouched: ${f}"
printf '%s\n' "$out" | awk -F'|' '$1=="HIT"{printf "      found %s entry: build %s (offset %s)\n",$4,$3,$2}'
((fail_n++)) ;;
3) rm -f "$tmp"; err "  build ${WIN10_BUILD} is not valid for ${WIN10_WINVER} (win10: 10000-21999, win11: 22000-40000)"; ((fail_n++)) ;;
*) rm -f "$tmp"; err "  patch failed for ${f} (rc=${rc})"; ((fail_n++)) ;;
esac
done <<< "$files"
echo
header
if (( fail_n == 0 )); then
ok "Build table ready: ${done_n} patched, ${same_n} already correct"
info "Restart the terminals so MT5 reloads it:  sudo heysolo  ->  R1, R2, ..."
else
warn "${done_n} patched, ${same_n} already correct, ${fail_n} problem(s) - see messages above"
fi
header
(( fail_n == 0 ))
}

buildpatch_restore() {
local files f bkp tmp n=0
files="$(bp_find_ntdll)"
if [[ -z "$files" ]]; then err "Could not find Wine's ntdll.dll (set WINE_ROOT=/path/to/wine)."; return 1; fi
while IFS= read -r f; do
[[ -z "$f" ]] && continue
bkp="${f}.orig-build"
if [[ ! -f "$bkp" ]]; then info "  no backup for ${f} - nothing to restore"; continue; fi
if bp_backup_stale "$f" "$bkp"; then warn "  Wine was updated after the backup was made - ${f} is already the new original, left alone"; continue; fi
tmp="$(mktemp "${f}.bptmp.XXXXXX" 2>/dev/null)"
if [[ -n "$tmp" ]] && cp -a "$bkp" "$tmp" 2>/dev/null && mv -f "$tmp" "$f" 2>/dev/null; then
ok "  restored ${f}"
((n++))
else
rm -f "$tmp" 2>/dev/null
err "  restore failed for ${f}"
fi
done <<< "$files"
info "Restored ${n} file(s). Restart the terminals to take effect."
}

buildpatch_menu() {
local CH
echo
header
title "WINDOWS BUILD PATCH - Wine's built-in version table"
header
echo -e "  wine:    ${BOLD}$(wine_version_string)${NC}"
echo -e "  profile: ${BOLD}$(current_profile_line)${NC}"
echo -e "  ${DIM}MT5 reads its Windows build from Wine's table, not from the registry.${NC}"
echo
echo -e "  ${BOLD}1)${NC} Patch Wine so ${WIN10_WINVER} reports build ${WIN10_BUILD}"
echo -e "  ${BOLD}2)${NC} Show status"
echo -e "  ${BOLD}3)${NC} Restore original ntdll.dll ${DIM}(undo)${NC}"
echo -e "  ${BOLD}0)${NC} Cancel"
echo
read -rp "Choice [${BOLD}1${NC}]: " CH || CH=""
CH="${CH:-1}"
case "${CH// /}" in
1) buildpatch_apply ;;
2) buildpatch_status ;;
3) buildpatch_restore ;;
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
echo -e "  ${BOLD}B)${NC} Make MT5 show the profile build (patch Wine's version table)  ${DIM}(patch / status / restore)${NC}"
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
4) show_status; read -rp "Press Enter to continue..." _ ;;
h|H) hide_wine_menu; read -rp "Press Enter to continue..." _ ;;
b|B) buildpatch_menu; read -rp "Press Enter to continue..." _ ;;
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
echo "Usage: wine-compliance.sh [menu|apply|test|revert|status|version|buildpatch|hidewine] [slug]"
echo
echo "Commands:"
echo "  menu              - Interactive menu (default)"
echo "  apply [slug]      - Apply compliance to all or specific terminal"
echo "  test [slug]       - Test compliance on all or specific terminal"
echo "  revert [slug]     - Revert compliance from all or specific terminal"
echo "  status            - Show compliance status for all terminals"
echo "  version [n|build] - Pick a Windows profile (preset number or build, e.g. 19045)"
echo "  buildpatch [status|restore] - Make Wine's ntdll report the profile build (MT5 reads it from there)"
echo "  hidewine [slug]   - Patch terminal64.exe (no slug = menu: all or pick one)"
echo "  hidewine all      - Patch every terminal"
echo "  hidewine restore [slug|all] - Undo the patch from the .orig-wine-detect backup"
echo "  hidewine diagnose <slug>    - Launch the terminal and capture the full wine log"
echo "  hidewine log [n]  - Show the hide-wine log (default 120 lines)"
echo "  hidewine verify [slug] - After a restart, read the real Journal OS line and check for Wine / Linux"
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
buildpatch|build)
case "${2:-}" in
"") buildpatch_menu ;;
apply) buildpatch_apply ;;
status) buildpatch_status ;;
restore) buildpatch_restore ;;
*) usage; exit 1 ;;
esac
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
verify|check) if [[ -n "${3:-}" ]]; then hide_wine_verify_slug "$3"; else hide_wine_verify_all; fi ;;
*) HW_SKIP_CONFIRM=1 hide_wine_apply_one "$2" ;;
esac
;;
version|profile)
if [[ -n "${2:-}" ]]; then
if [[ "$2" =~ ^[0-9]{4,6}$ ]]; then
matched=0
for idx in "${!WIN_PRESETS[@]}"; do
IFS='|' read -r _l pb _r <<< "${WIN_PRESETS[$idx]}"
if [[ "$pb" == "$2" ]]; then set_profile_from_preset $((idx+1)); matched=1; break; fi
done
if (( matched == 0 )); then
WIN10_BUILD="$2"
if (( WIN10_BUILD >= 22000 )); then WIN10_WINVER="win11"; else WIN10_WINVER="win10"; fi
fi
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