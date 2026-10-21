#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec sudo /bin/sh "${PROJECT_DIR}/SysTFTP/Resources/port_forwarding.sh" "${1:-enable}"
