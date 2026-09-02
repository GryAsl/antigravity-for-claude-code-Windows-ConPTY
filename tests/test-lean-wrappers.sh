#!/usr/bin/env bash
# Contract tests for agy-scout / agy-review. No network or real model calls.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
REVIEW="$ROOT/scripts/agy-review.sh"
SCOUT="$ROOT/scripts/agy-scout.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

ok() { echo "ok: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
has() { grep -qF -- "$2" "$1"; }
lacks() { ! grep -qF -- "$2" "$1"; }

STUB="$TMP/agy-delegate"
cat >"$STUB" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$AGY_CAPTURE.args"
printf 'call\n' >>"$AGY_CAPTURE.calls"
pwd >"$AGY_CAPTURE.cwd"
cat >"$AGY_CAPTURE.stdin"
if [ "${AGY_STUB_OVERSIZE:-0}" = 1 ]; then
  printf 'VERDICT: CONFIRMED\nFINDINGS:\n- none\nTEST_GAPS:\n- none\nCOMMIT_SUBJECT: test: fixture\n'
  awk 'BEGIN { for (i=0; i<9000; i++) printf "x" }'
  printf '\nDIGEST: oversized\n'
elif printf '%s\n' "$@" | grep -q -- '--mode'; then
  printf 'FINDINGS:\n- fixture.cs:1 — evidence\nRISKS_OR_GAPS:\n- none\nNEXT_LIKELY_GAP: none\nDIGEST: scout saw the fixture\n'
else
  printf 'VERDICT: CONFIRMED\nFINDINGS:\n- none\nTEST_GAPS:\n- none\nCOMMIT_SUBJECT: test: review fixture\nDIGEST: patch matches the goal\n'
fi
STUB
chmod +x "$STUB"

REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.name Test
git -C "$REPO" config user.email test@example.invalid
printf 'base-a\n' >"$REPO/a.txt"
printf 'base-b\n' >"$REPO/b.txt"
git -C "$REPO" add a.txt b.txt
git -C "$REPO" -c commit.gpgSign=false commit -qm baseline
printf 'STAGED_SENTINEL_41A7\n' >>"$REPO/a.txt"
for i in $(seq 1 30); do printf 'staged-padding-%02d\n' "$i" >>"$REPO/a.txt"; done
git -C "$REPO" add a.txt
printf 'WORKTREE_SENTINEL_92BC\n' >>"$REPO/b.txt"
printf 'UNTRACKED_SENTINEL_F00D\n' >"$REPO/new.txt"

CAP="$TMP/worktree"
if AGY_DELEGATE="$STUB" AGY_CAPTURE="$CAP" "$REVIEW" --dir "$REPO" --goal "only append fixture lines" >"$CAP.out" 2>"$CAP.err"; then
  has "$CAP.stdin" STAGED_SENTINEL_41A7 && has "$CAP.stdin" WORKTREE_SENTINEL_92BC \
    && lacks "$CAP.stdin" UNTRACKED_SENTINEL_F00D && ok "worktree patch goes to agy; untracked contents do not" \
    || bad "worktree payload scope"
  has "$CAP.args" flash && has "$CAP.args" --digest && has "$CAP.out" 'VERDICT: CONFIRMED' \
    && lacks "$CAP.out" STAGED_SENTINEL_41A7 && ok "Claude-facing output is only the compact verdict" \
    || bad "compact review output"
  has "$CAP.err" 'untracked contents are excluded' && ok "untracked review gap is explicit" \
    || bad "untracked warning"
  [ "$(cat "$CAP.cwd")" != "$REPO" ] && ok "blind review runs outside the caller repository" \
    || bad "blind review working directory isolation"
else
  bad "worktree review exits zero"
fi

CAP="$TMP/staged"
if AGY_DELEGATE="$STUB" AGY_CAPTURE="$CAP" "$REVIEW" --dir "$REPO" --staged >"$CAP.out" 2>"$CAP.err"; then
  has "$CAP.stdin" STAGED_SENTINEL_41A7 && lacks "$CAP.stdin" WORKTREE_SENTINEL_92BC \
    && ok "--staged isolates the index" || bad "--staged scope"
else
  bad "staged review exits zero"
fi

CAP="$TMP/scout"
if AGY_DELEGATE="$STUB" AGY_CAPTURE="$CAP" "$SCOUT" --dir "$REPO" "trace the fixture" >"$CAP.out" 2>"$CAP.err"; then
  has "$CAP.args" flash && has "$CAP.args" plan && has "$CAP.args" "$REPO" \
    && has "$CAP.args" 'READ-ONLY repository investigation' && has "$CAP.args" 'NEXT_LIKELY_GAP' \
    && ok "scout builds the fixed read-only Flash contract" || bad "scout contract"
  has "$CAP.out" 'DIGEST: scout saw the fixture' && ok "scout returns only its digest" \
    || bad "scout output"
else
  bad "scout exits zero"
fi

CAP="$TMP/oversize"
set +e
AGY_DELEGATE="$STUB" AGY_CAPTURE="$CAP" AGY_REVIEW_MAX_OUTPUT_CHARS=200 \
  AGY_STUB_OVERSIZE=1 "$REVIEW" --dir "$REPO" --staged >"$CAP.out" 2>"$CAP.err"
RC=$?
set -e
if [ "$RC" -ne 0 ] && [ ! -s "$CAP.out" ] && has "$CAP.err" 'raw response suppressed'; then
  ok "oversized model output is not leaked to Claude"
else
  bad "oversized output guard"
fi

set +e
AGY_DELEGATE="$STUB" AGY_CAPTURE="$TMP/reject" "$REVIEW" --dir "$REPO" --range '-c' >"$TMP/reject.out" 2>"$TMP/reject.err"
RC=$?
set -e
if [ "$RC" -ne 0 ] && has "$TMP/reject.err" "cannot begin with '-'"; then
  ok "option-shaped Git ranges are rejected"
else
  bad "range option injection guard"
fi

CAP="$TMP/chunked"
if AGY_DELEGATE="$STUB" AGY_CAPTURE="$CAP" AGY_REVIEW_CHUNK_BYTES=200 \
  "$REVIEW" --dir "$REPO" --staged >"$CAP.out" 2>"$CAP.err"; then
  CALLS="$(wc -l <"$CAP.calls" | tr -d '[:space:]')"
  if [ "$CALLS" -gt 1 ] && has "$CAP.out" 'VERDICT: CONFIRMED' \
    && lacks "$CAP.out" STAGED_SENTINEL_41A7 && has "$CAP.stdin" 'discard findings caused only by a chunk'; then
    ok "Windows-sized chunks are privately reviewed and synthesized"
  else
    bad "chunked review synthesis"
  fi
else
  bad "chunked review exits zero"
fi

echo "wrapper PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
