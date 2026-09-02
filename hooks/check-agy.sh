#!/usr/bin/env bash
#
# SessionStart hook: lightweight check that the Antigravity CLI (`agy`) is usable.
# Warns on stderr but NEVER fails the session (always exits 0). The full health
# check lives in scripts/doctor.sh — this one stays fast (no `agy models` network
# call) so it doesn't slow every session start.
#
set -uo pipefail

on_windows_native() {
  case "${OSTYPE:-}" in msys*|cygwin*|win32) return 0 ;; esac
  case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) return 0 ;; esac
  return 1
}

agy_available() {
  command -v agy >/dev/null 2>&1 || \
    { [ -n "${AGY_PATH:-}" ] && [ -f "$AGY_PATH" ]; } || \
    { [ -n "${LOCALAPPDATA:-}" ] && [ -f "$LOCALAPPDATA/agy/bin/agy.exe" ]; }
}

if ! agy_available; then
  echo "[antigravity] agy not on PATH — install the Antigravity CLI to enable delegation:" >&2
  echo "[antigravity]   https://antigravity.google/docs/cli-using" >&2
  exit 0
fi

if on_windows_native; then
  # Never launch agy directly from this headless hook: native Windows needs the
  # ConPTY adapter, and the full end-to-end check belongs to agy-doctor.
  if [ -n "${AGY_BRIDGE_PYTHON:-}" ]; then
    "$AGY_BRIDGE_PYTHON" -c 'import agy_headless_bridge, winpty' >/dev/null 2>&1 || \
      echo "[antigravity] Windows ConPTY bridge is not importable by AGY_BRIDGE_PYTHON." >&2
  elif command -v py >/dev/null 2>&1; then
    py -3 -c 'import agy_headless_bridge, winpty' >/dev/null 2>&1 || \
      echo "[antigravity] Windows ConPTY bridge missing — run: py -3 -m pip install -U agy-headless-bridge" >&2
  elif command -v python >/dev/null 2>&1; then
    python -c 'import agy_headless_bridge, winpty' >/dev/null 2>&1 || \
      echo "[antigravity] Windows ConPTY bridge missing from the active Python." >&2
  else
    echo "[antigravity] Windows ConPTY bridge needs Python >= 3.9 (or AGY_BRIDGE_PYTHON)." >&2
  fi
elif ! agy --version >/dev/null 2>&1; then
  echo "[antigravity] agy is on PATH but '--version' failed — it may need authentication (run \`agy\` once)." >&2
fi

exit 0
