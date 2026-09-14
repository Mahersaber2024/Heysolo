#!/usr/bin/env bash
set -uo pipefail

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  for c in /opt/heysolo/scripts/wine-compliance.sh /opt/heysolo/wine/wine-compliance.sh \
           /opt/heysolo/wine-compliance.sh /usr/local/bin/wine-compliance.sh; do
    [[ -f "$c" ]] && TARGET="$c" && break
  done
fi
[[ -z "$TARGET" ]] && TARGET=$(find / -name 'wine-compliance.sh' -type f 2>/dev/null | head -1)
if [[ -z "$TARGET" || ! -f "$TARGET" ]]; then
  echo "wine-compliance.sh not found. Run:  sudo bash $0 /full/path/to/wine-compliance.sh"
  exit 1
fi

BACKUP="${TARGET}.bak.$(date +%s)"
echo "Target : $TARGET"
echo "Backup : $BACKUP"
cp -a "$TARGET" "$BACKUP"

PREVIEW_BLOCK=$(mktemp)
cat > "$PREVIEW_BLOCK" <<'PREVIEW_EOF'
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
PREVIEW_EOF

python3 - "$TARGET" "$PREVIEW_BLOCK" <<'PY'
import re, sys
target, blockfile = sys.argv[1], sys.argv[2]
s = open(target).read()
orig = s
block = open(blockfile).read()
report = []

def note(label, n):
    report.append(("  OK   " if n else "  SKIP ") + "%s: %d" % (label, n))

pat = re.compile(r"""wine cmd /c '(reg query [^']*)'""")
n = len(pat.findall(s)); note("wine cmd -> wine reg query", n)
s = pat.sub(lambda m: m.group(1).replace('\\\\', '\\'), s)

o = r"""grep -oP '(?<=REG_SZ\s{4}).*'"""
nn = r"""sed -n 's/.*REG_SZ[[:space:]]*//p'"""
note("REG_SZ parser hardened", s.count(o)); s = s.replace(o, nn)

o6 = """as_mt5 "WINEPREFIX='${wineprefix}' rm -f ~/.wine/dosdevices/c:/windows/system32/wine*.dll" 2>/dev/null || true"""
n6 = """rm -f "${wineprefix}"/drive_c/windows/system32/wine*.dll 2>/dev/null || true"""
note("step 6 uses the real prefix", s.count(o6)); s = s.replace(o6, n6)

o7 = '''"*ntdll"="native,builtin"
"*kernel32"="native,builtin"
"*user32"="native,builtin"
"*advapi32"="native,builtin"
"*shell32"="native,builtin"
"*ole32"="native,builtin"
"*oleaut32"="native,builtin"
"*msvcrt"="native,builtin"
"*rpcrt4"="native,builtin"
"*winemenubuilder.exe"=""'''
note("dangerous core DLL overrides removed", s.count(o7))
s = s.replace(o7, '"*winemenubuilder.exe"=""')

if 'preview_prefix_changes' not in s:
    a = "apply_compliance_to_prefix() {"
    if s.count(a) == 1:
        s = s.replace(a, block + "\n" + a); note("preview functions added", 1)
    else:
        note("preview functions added", 0)

    oh = '''info "Applying compliance to ${slug} (${wineprefix})..."
log "Applying compliance to ${slug} (${wineprefix}) - started"'''
    nh = '''if [[ "${COMPLIANCE_PREVIEW_SHOWN:-0}" != "1" ]]; then
echo
header
title "CURRENT WINE REGISTRY (read-only preview)"
header
preview_prefix_changes "$wineprefix" "$slug" || return 1
confirm_preview "${PREVIEW_CHANGES:-0}" || return 1
COMPLIANCE_PREVIEW_SHOWN=1
fi

''' + oh
    note("preview hooked into single apply", s.count(oh)); s = s.replace(oh, nh)

    oa = '''title "APPLYING WINE COMPLIANCE TO ALL TERMINALS"
header
local success=0 failed=0'''
    na = '''title "CURRENT WINE REGISTRY - ALL TERMINALS (read-only preview)"
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
local success=0 failed=0'''
    note("preview hooked into apply-all", s.count(oa)); s = s.replace(oa, na)

    om = '''1) apply_compliance_all; read -rp "Press Enter to continue..." _ ;;'''
    note("menu 1 resets preview", s.count(om))
    s = s.replace(om, '''1) COMPLIANCE_PREVIEW_SHOWN=0; apply_compliance_all; read -rp "Press Enter to continue..." _ ;;''')

    os_ = '''IFS='|' read -r slug wineprefix <<< "${SLUGS[$((idx-1))]}"
apply_compliance_to_prefix "$wineprefix" "$slug"'''
    note("menu 5 resets preview", s.count(os_))
    s = s.replace(os_, '''IFS='|' read -r slug wineprefix <<< "${SLUGS[$((idx-1))]}"
COMPLIANCE_PREVIEW_SHOWN=0
apply_compliance_to_prefix "$wineprefix" "$slug"''')
else:
    note("preview already present, skipped", 0)

print("\n".join(report))
if s == orig:
    print("\nNothing changed - already fully patched.")
    sys.exit(2)
open(target, 'w').write(s)
print("\nWritten.")
PY
rc=$?
rm -f "$PREVIEW_BLOCK"

if [[ $rc -eq 2 ]]; then
  rm -f "$BACKUP"
  exit 0
fi
if [[ $rc -ne 0 ]]; then
  echo "Patch step failed - restoring backup"
  cp -a "$BACKUP" "$TARGET"
  exit 1
fi
if bash -n "$TARGET"; then
  chmod +x "$TARGET" 2>/dev/null || true
  echo
  echo "Syntax OK. Try it:"
  echo "  sudo heysolo   ->  press S  ->  press 1"
  echo "or directly:"
  echo "  sudo bash $TARGET apply"
else
  echo "SYNTAX ERROR - restoring backup"
  cp -a "$BACKUP" "$TARGET"
  exit 1
fi
