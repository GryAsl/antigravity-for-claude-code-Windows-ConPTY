#!/usr/bin/env bash
#
# SessionStart hook: inject this plugin's COST-AWARE routing policy as session
# context, so the discipline (small tasks eligible, Flash by default, neutral task
# contracts, lean context, independent verification) applies even when the skill isn't
# explicitly invoked. Prints the hookSpecificOutput JSON on stdout.
#
# Toggle off via plugin userConfig `coding_policy` (env CLAUDE_PLUGIN_OPTION_CODING_POLICY:
# off / false / 0 / no / disabled). Default: on.
#
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

raw="$(printf '%s' "${CLAUDE_PLUGIN_OPTION_CODING_POLICY:-on}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
case "$raw" in
  off|false|0|no|disabled) exit 0 ;;
esac

cat "$HERE/policy-context.json"
exit 0
