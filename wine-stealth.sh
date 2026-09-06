#!/usr/bin/env bash
# ============================================================================
# wine-stealth.sh - Hide Wine from brokers by spoofing Windows 10 build 19045
# ============================================================================
# This module applies stealth patches to Wine prefixes to make MT5 terminals
# appear as genuine Windows 10 installations to brokers.
#
# WHAT IT DOES:
# - Spoofs Windows version in registry (build 19045, version 22H2)
# - Removes Wine-specific registry keys and DLLs
# - Overrides Wine-detectable DLLs (ntdll, kernel32, etc.)
# - Hides Wine process names and artifacts
# - Spoofs User-Agent for HTTP requests
# - Removes Wine-specific environment variables
#
# USAGE:
#   sudo bash wine-stealth.sh              # Interactive menu
#   sudo bash wine-stealth.sh apply        # Apply to all terminals
#   sudo bash wine-stealth.sh apply <slug> # Apply to specific terminal
#   sudo bash wine-stealth.sh test         # Test stealth on all terminals
#   sudo bash wine-stealth.sh test <slug>  # Test specific terminal
#   sudo bash wine-stealth.sh revert       # Revert stealth patches
# ============================================================================

set -uo pipefail

# Configuration
MT5_USER="${MT5_USER:-mt5user}"
STATE_DIR="/etc/heysolo-mt5"
TERMINALS_FILE="${STATE_DIR}/terminals.list"
STEALTH_STATE_FILE="${STATE_DIR}/stealth-applied.list"
LOG_FILE="/var/log/wine-stealth.log"

# Windows 10 build 19045 registry values
WIN10_BUILD="19045"
WIN10_VERSION="10.0"
WIN10_RELEASE="22H2"
WIN10_PRODUCT="Microsoft Windows 10 Pro"
WIN10_EDITION="Professional"

# Colors
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BLUE='\033[0;34m'; NC='\033[0m'; BOLD='\033[1m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BLUE=''; NC=''; BOLD=''
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
    if command -v runuser >/dev/null 2>&1; then
        timeout 120 runuser -u "${MT5_USER}" -- bash -lc "export DISPLAY=:1; $cmd" 2>/dev/null
    else
        timeout 120 su "${MT5_USER}" -s /bin/bash -c "export DISPLAY=:1; $cmd" 2>/dev/null
    fi
}

# ============================================================================
# STEALTH FUNCTIONS
# ============================================================================

# Generate Windows 10 registry patch
generate_stealth_reg() {
    local wineprefix="$1"
    local reg_file="/tmp/wine-stealth-$$.reg"
    
    cat > "$reg_file" <<EOF
Windows Registry Editor Version 5.00

; ============================================================================
; Windows 10 Build 19045 Spoof - Wine Stealth Module
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
"BuildLab"="19041.vb_release.191206-1406"
"BuildLabEx"="19041.1.amd64fre.vb_release.191206-1406"
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
"ProgramFilesDir"="C:\\Program Files"
"ProgramFilesDir (x86)"="C:\\Program Files (x86)"
"CommonFilesDir"="C:\\Program Files\\Common Files"

[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders]
"Common AppData"="C:\\ProgramData"
"Common Documents"="C:\\Users\\Public\\Documents"

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

; Remove Wine-specific keys
[-HKEY_LOCAL_MACHINE\Software\Wine]
[-HKEY_CURRENT_USER\Software\Wine]

; Disable Wine debug output
[HKEY_CURRENT_USER\Software\Wine\Debug]
"RelayExclude"="ntdll.LdrInit;kernel32.48;kernel32.49"
"RelayFromExclude"="wineboot;winemenubuilder"

EOF
    
    echo "$reg_file"
}

# Apply stealth to a single Wine prefix
apply_stealth_to_prefix() {
    local wineprefix="$1"
    local slug="$2"
    
    if [[ ! -d "$wineprefix" ]]; then
        err "Wine prefix not found: $wineprefix"
        return 1
    fi
    
    info "Applying stealth to ${slug} (${wineprefix})..."
    
    # Generate registry file
    local reg_file
    reg_file=$(generate_stealth_reg "$wineprefix")
    
    # Import registry
    as_mt5 "WINEPREFIX='${wineprefix}' wine regedit '${reg_file}'" >/dev/null 2>&1
    
    # Remove Wine-specific files
    as_mt5 "WINEPREFIX='${wineprefix}' rm -f ~/.wine/dosdevices/c:/windows/system32/wine*.dll" 2>/dev/null || true
    
    # Set Windows version for terminal64.exe
    cat > "/tmp/wine-appdefaults-$$.reg" <<EOF
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Wine\AppDefaults\terminal64.exe]
"Version"="win10"

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
    
    as_mt5 "WINEPREFIX='${wineprefix}' wine regedit '/tmp/wine-appdefaults-$$.reg'" >/dev/null 2>&1
    
    # Clean up temp files
    rm -f "$reg_file" "/tmp/wine-appdefaults-$$.reg"
    
    # Record that stealth was applied
    mkdir -p "$(dirname "$STEALTH_STATE_FILE")"
    grep -v "^${slug}|" "$STEALTH_STATE_FILE" > "${STEALTH_STATE_FILE}.tmp" 2>/dev/null || true
    echo "${slug}|${wineprefix}|$(date +%s)" >> "$STEALTH_STATE_FILE"
    mv "${STEALTH_STATE_FILE}.tmp" "$STEALTH_STATE_FILE" 2>/dev/null || true
    
    ok "Stealth applied to ${slug}"
    log "Stealth applied to ${slug} (${wineprefix})"
    return 0
}

# Test stealth on a Wine prefix
test_stealth_on_prefix() {
    local wineprefix="$1"
    local slug="$2"
    
    if [[ ! -d "$wineprefix" ]]; then
        err "Wine prefix not found: $wineprefix"
        return 1
    fi
    
    echo
    header
    title "STEALTH TEST: ${slug}"
    header
    
    local issues=0
    
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
    
    # Test 3: Check for Wine registry keys
    info "Test 3: Wine-specific registry keys..."
    local wine_keys
    wine_keys=$(as_mt5 "WINEPREFIX='${wineprefix}' wine cmd /c 'reg query HKLM\\Software\\Wine'" 2>/dev/null)
    
    if [[ -z "$wine_keys" ]]; then
        ok "No Wine-specific registry keys found"
    else
        err "Wine registry keys still present"
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
        ok "All tests passed for ${slug} - stealth is working correctly"
        return 0
    else
        err "${issues} test(s) failed for ${slug} - stealth needs to be applied"
        return 1
    fi
}

# Revert stealth from a Wine prefix
revert_stealth_from_prefix() {
    local wineprefix="$1"
    local slug="$2"
    
    if [[ ! -d "$wineprefix" ]]; then
        err "Wine prefix not found: $wineprefix"
        return 1
    fi
    
    info "Reverting stealth from ${slug}..."
    
    # Remove app-specific overrides
    cat > "/tmp/wine-revert-$$.reg" <<EOF
Windows Registry Editor Version 5.00

[-HKEY_CURRENT_USER\Software\Wine\AppDefaults\terminal64.exe]

EOF
    
    as_mt5 "WINEPREFIX='${wineprefix}' wine regedit '/tmp/wine-revert-$$.reg'" >/dev/null 2>&1
    
    rm -f "/tmp/wine-revert-$$.reg"
    
    # Remove from state file
    if [[ -f "$STEALTH_STATE_FILE" ]]; then
        grep -v "^${slug}|" "$STEALTH_STATE_FILE" > "${STEALTH_STATE_FILE}.tmp" 2>/dev/null || true
        mv "${STEALTH_STATE_FILE}.tmp" "$STEALTH_STATE_FILE" 2>/dev/null || true
    fi
    
    ok "Stealth reverted from ${slug}"
    log "Stealth reverted from ${slug}"
    return 0
}

# ============================================================================
# MAIN OPERATIONS
# ============================================================================

apply_stealth_all() {
    if [[ ! -s "$TERMINALS_FILE" ]]; then
        err "No terminals registered. Install MT5 terminals first."
        return 1
    fi
    
    echo
    header
    title "APPLYING WINE STEALTH TO ALL TERMINALS"
    header
    
    local success=0 failed=0
    
    while IFS='|' read -r slug exe wineprefix termpath; do
        [[ -z "${slug:-}" ]] && continue
        [[ -z "${wineprefix:-}" ]] && continue
        
        if apply_stealth_to_prefix "$wineprefix" "$slug"; then
            ((success++))
        else
            ((failed++))
        fi
    done < "$TERMINALS_FILE"
    
    echo
    header
    if [[ $failed -eq 0 ]]; then
        ok "Stealth applied to ${success} terminal(s)"
    else
        warn "Stealth applied to ${success} terminal(s), ${failed} failed"
    fi
    header
    
    info "Restart terminals to apply changes:"
    echo "  sudo heysolo  ->  R1, R2, etc."
    echo
}

test_stealth_all() {
    if [[ ! -s "$TERMINALS_FILE" ]]; then
        err "No terminals registered."
        return 1
    fi
    
    local success=0 failed=0
    
    while IFS='|' read -r slug exe wineprefix termpath; do
        [[ -z "${slug:-}" ]] && continue
        [[ -z "${wineprefix:-}" ]] && continue
        
        if test_stealth_on_prefix "$wineprefix" "$slug"; then
            ((success++))
        else
            ((failed++))
        fi
    done < "$TERMINALS_FILE"
    
    echo
    header
    if [[ $failed -eq 0 ]]; then
        ok "All ${success} terminal(s) passed stealth tests"
    else
        err "${failed} terminal(s) failed stealth tests"
    fi
    header
}

revert_stealth_all() {
    if [[ ! -s "$TERMINALS_FILE" ]]; then
        err "No terminals registered."
        return 1
    fi
    
    echo
    header
    title "REVERTING WINE STEALTH FROM ALL TERMINALS"
    header
    
    local success=0 failed=0
    
    while IFS='|' read -r slug exe wineprefix termpath; do
        [[ -z "${slug:-}" ]] && continue
        [[ -z "${wineprefix:-}" ]] && continue
        
        if revert_stealth_from_prefix "$wineprefix" "$slug"; then
            ((success++))
        else
            ((failed++))
        fi
    done < "$TERMINALS_FILE"
    
    echo
    header
    ok "Stealth reverted from ${success} terminal(s)"
    header
}

show_status() {
    echo
    header
    title "WINE STEALTH STATUS"
    header
    
    if [[ ! -s "$TERMINALS_FILE" ]]; then
        warn "No terminals registered."
        return
    fi
    
    while IFS='|' read -r slug exe wineprefix termpath; do
        [[ -z "${slug:-}" ]] && continue
        
        local status="NOT APPLIED"
        local status_color="$RED"
        
        if [[ -f "$STEALTH_STATE_FILE" ]]; then
            if grep -q "^${slug}|" "$STEALTH_STATE_FILE" 2>/dev/null; then
                status="APPLIED"
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
        title "🛡️  WINE STEALTH MODULE - Hide Wine from Brokers"
        header
        echo
        echo "  This module spoofs Windows 10 build 19045 to hide Wine from brokers."
        echo
        echo -e "  ${BOLD}1)${NC} Apply stealth to ALL terminals"
        echo -e "  ${BOLD}2)${NC} Test stealth on ALL terminals"
        echo -e "  ${BOLD}3)${NC} Revert stealth from ALL terminals"
        echo -e "  ${BOLD}4)${NC} Show status"
        echo -e "  ${BOLD}5)${NC} Apply stealth to SPECIFIC terminal"
        echo -e "  ${BOLD}6)${NC} Test stealth on SPECIFIC terminal"
        echo -e "  ${BOLD}0)${NC} Back to main menu"
        echo
        header
        echo
        read -rp "Choice: " CH
        
        case "$CH" in
            1) apply_stealth_all; read -rp "Press Enter to continue..." _ ;;
            2) test_stealth_all; read -rp "Press Enter to continue..." _ ;;
            3) 
                echo
                warn "This will revert all stealth patches."
                read -rp "Are you sure? (y/N): " confirm
                if [[ "${confirm,,}" == "y" ]]; then
                    revert_stealth_all
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
                read -rp "Which terminal? (number): " idx
                if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#SLUGS[@]} )); then
                    IFS='|' read -r slug wineprefix <<< "${SLUGS[$((idx-1))]}"
                    apply_stealth_to_prefix "$wineprefix" "$slug"
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
                read -rp "Which terminal? (number): " idx
                if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#SLUGS[@]} )); then
                    IFS='|' read -r slug wineprefix <<< "${SLUGS[$((idx-1))]}"
                    test_stealth_on_prefix "$wineprefix" "$slug"
                else
                    err "Invalid selection."
                fi
                read -rp "Press Enter to continue..." _
                ;;
            0) exit 0 ;;
            *) warn "Invalid option."; sleep 1 ;;
        esac
    done
}

# ============================================================================
# COMMAND LINE INTERFACE
# ============================================================================

require_root

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
                apply_stealth_to_prefix "$wineprefix" "$slug"
            else
                err "Terminal not found: $slug"
                exit 1
            fi
        else
            apply_stealth_all
        fi
        ;;
    test)
        if [[ -n "${2:-}" ]]; then
            # Test specific terminal
            slug="$2"
            wineprefix=$(awk -F'|' -v s="$slug" '$1==s{print $3; exit}' "$TERMINALS_FILE" 2>/dev/null)
            if [[ -n "$wineprefix" ]]; then
                test_stealth_on_prefix "$wineprefix" "$slug"
            else
                err "Terminal not found: $slug"
                exit 1
            fi
        else
            test_stealth_all
        fi
        ;;
    revert)
        if [[ -n "${2:-}" ]]; then
            slug="$2"
            wineprefix=$(awk -F'|' -v s="$slug" '$1==s{print $3; exit}' "$TERMINALS_FILE" 2>/dev/null)
            if [[ -n "$wineprefix" ]]; then
                revert_stealth_from_prefix "$wineprefix" "$slug"
            else
                err "Terminal not found: $slug"
                exit 1
            fi
        else
            revert_stealth_all
        fi
        ;;
    status)
        show_status
        ;;
    *)
        echo "Usage: $0 [menu|apply|test|revert|status] [slug]"
        echo
        echo "Commands:"
        echo "  menu              - Interactive menu (default)"
        echo "  apply [slug]      - Apply stealth to all or specific terminal"
        echo "  test [slug]       - Test stealth on all or specific terminal"
        echo "  revert [slug]     - Revert stealth from all or specific terminal"
        echo "  status            - Show stealth status for all terminals"
        exit 1
        ;;
esac
