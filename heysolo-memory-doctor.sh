#!/usr/bin/env bash
set -Eeuo pipefail

echo "HeySolo memory and terminal diagnostic"
echo
free -h
echo
echo "Swap devices:"
swapon --show --bytes 2>/dev/null || true
echo
echo "Memory pressure:"
cat /proc/pressure/memory 2>/dev/null || true
echo
echo "HeySolo terminal processes:"
pgrep -a -u mt5user -f 'terminal(64)?\.exe|wineserver|wine-preloader' 2>/dev/null || echo "none"
echo
echo "Recent OOM events:"
journalctl -k -b --no-pager 2>/dev/null | grep -iE 'out of memory|oom-killer|killed process' | tail -20 || true
echo
echo "Current tuning:"
for key in vm.swappiness vm.vfs_cache_pressure vm.page-cluster; do
  printf '%s=' "$key"
  sysctl -n "$key" 2>/dev/null || echo unavailable
done
echo
echo "Registered terminals:"
cat /etc/heysolo-mt5/terminals.list 2>/dev/null || echo "not found"
