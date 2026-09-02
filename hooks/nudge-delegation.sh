#!/usr/bin/env bash
#
# UserPromptSubmit hook: a cheap, deterministic nudge toward delegation when the
# user's prompt LOOKS like bulk work. Small tasks remain eligible through the
# global/session policy; this heuristic stays conservative to avoid context spam.
#
# Design principle: this supplies judgment MATERIAL — the DECISION stays with
# Claude. It never fires the wrapper itself; the fixed note only reminds Claude
# that the plugin is available.
#
# Heuristic is deliberately conservative (volume/fan-out phrases, EN + JA), and
# the nudge text is a FIXED string — the user's prompt is never echoed back into
# the context (no escaping/injection surface).
#
# Toggle via plugin userConfig `delegation_nudge`
# (env CLAUDE_PLUGIN_OPTION_DELEGATION_NUDGE: off/false/0/no/disabled). Default: on.
#
set -uo pipefail

raw="$(printf '%s' "${CLAUDE_PLUGIN_OPTION_DELEGATION_NUDGE:-on}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
case "$raw" in off|false|0|no|disabled) exit 0 ;; esac

IN="$(cat 2>/dev/null || true)"
[ -n "$IN" ] || exit 0

# Extract ONLY the prompt field (matching on the whole payload would false-positive
# on cwd/paths). Git Bash can expose a broken Windows Store `python3` alias, so probe
# the interpreter before using it and fall back to the Windows Python Launcher.
PY_CMD=()
if [ -n "${AGY_BRIDGE_PYTHON:-}" ] && "$AGY_BRIDGE_PYTHON" -c 'import sys' >/dev/null 2>&1; then
  PY_CMD=("$AGY_BRIDGE_PYTHON")
elif command -v python3 >/dev/null 2>&1 && python3 -c 'import sys' >/dev/null 2>&1; then
  PY_CMD=(python3)
elif command -v py >/dev/null 2>&1 && py -3 -c 'import sys' >/dev/null 2>&1; then
  PY_CMD=(py -3)
elif command -v python >/dev/null 2>&1 && python -c 'import sys' >/dev/null 2>&1; then
  PY_CMD=(python)
else
  exit 0
fi

PROMPT="$(printf '%s' "$IN" | "${PY_CMD[@]}" -c 'import json,sys
try: print(json.load(sys.stdin).get("prompt",""))
except Exception: pass' 2>/dev/null || true)"
[ -n "$PROMPT" ] || exit 0

# Already delegating explicitly? Stay quiet.
case "$PROMPT" in *antigravity*|*agy-delegate*|*agy-job*) exit 0 ;; esac

shopt -s nocasematch
HIT=0
case "$PROMPT" in
  *"all files"*|*"every file"*|*"across the codebase"*|*"entire codebase"*|*"whole repo"*| \
  *migrate*|*migration*|*"generate tests"*|*"test coverage"*|*"exhaustive test"*| \
  *scaffold*|*boilerplate*|*"deep research"*|*"web search"*| \
  *一括*|*全ファイル*|*すべてのファイル*|*網羅*|*移行*|*大量*|*横断*|*リポジトリ全体*)
    HIT=1 ;;
esac
shopt -u nocasematch
[ "$HIT" -eq 1 ] || exit 0

# Fixed nudge. Note the explicit "the judgment is yours" — this is material, not a mandate.
cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"[antigravity plugin] This prompt looks suitable for delegation. Proactively route a bounded unit to antigravity-delegate with explicit `--tier flash`, a neutral task contract, and digest-only output, then independently verify it. Small tasks are also eligible under the session policy; never reject solely for size. THE JUDGMENT IS YOURS; decide silently and do not mention this notice."}}
JSON
exit 0
