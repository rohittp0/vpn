#!/usr/bin/env bash
set -euo pipefail

# --- Config ---
SRC_DIR="/var/lib/docker/volumes/vpn_vpn-data/_data"
PORT="${PORT:-8000}"          # override with: PORT=9000 ./serve_vpn_files.sh <name>

usage() {
  echo "Usage: $0 <name>"
  echo "Copies <name>.mobileconfig, <name>.sswan, <name>.p12 from:"
  echo "  $SRC_DIR"
  echo "to a temporary folder and serves them via Python HTTP until you Ctrl+C."
  exit 1
}

[[ $# -eq 1 ]] || usage
NAME="$1"

# Verify source dir
if [[ ! -d "$SRC_DIR" ]]; then
  echo "Error: Source directory not found: $SRC_DIR" >&2
  exit 2
fi

# Prepare temp directory
TMP_DIR="$(mktemp -d -t vpnfiles.XXXXXX)"
cleanup() {
  echo -e "\nStopping server and cleaning up $TMP_DIR ..."
  rm -rf "$TMP_DIR"
}
trap cleanup INT TERM EXIT

# Required files
FILES=(
  "${NAME}.mobileconfig"
  "${NAME}.sswan"
  "${NAME}.p12"
)

# Copy files with checks
for f in "${FILES[@]}"; do
  src="$SRC_DIR/$f"
  if [[ ! -f "$src" ]]; then
    echo "Error: File not found: $src" >&2
    exit 3
  fi
  cp -v "$src" "$TMP_DIR/"
done

# (Optional) tighten permissions on the cert
if [[ -f "$TMP_DIR/${NAME}.p12" ]]; then
  chmod 600 "$TMP_DIR/${NAME}.p12" || true
fi

echo "Files copied to: $TMP_DIR"
echo "Launching HTTP server on port $PORT (serving $TMP_DIR)"
echo "Press Ctrl+C to stop."

# Try to show a reachable IP if available
HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}')" || true
if [[ -n "${HOST_IP:-}" ]]; then
  echo "Local URLs:"
  echo "  http://localhost:${PORT}/"
  echo "  http://${HOST_IP}:${PORT}/"
else
  echo "Local URL: http://localhost:${PORT}/"
fi

# Serve until interrupted
cd "$TMP_DIR"
# Use Python 3 if available; fall back to python
if command -v python3 >/dev/null 2>&1; then
  exec python3 -m http.server "$PORT" --bind 0.0.0.0
else
  exec python -m SimpleHTTPServer "$PORT"
fi
