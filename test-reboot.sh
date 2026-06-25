#!/usr/bin/env bash
# Test what happens on reboot.

set -euo pipefail

limactl stop k3s
sudo launchctl kickstart -k system/com.joeyguerra.lima-k3s
tail -f /var/log/lima-k3s.log
