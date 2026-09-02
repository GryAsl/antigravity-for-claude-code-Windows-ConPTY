---
description: Review a Git diff with a fresh Gemini Flash verifier without loading the raw patch into Claude's context.
argument-hint: "[--staged|--last|--range A..B] [--path PATH] [goal]"
---

Use the plugin's lean review wrapper. It captures the selected Git patch internally,
sends it directly to a fresh Gemini reviewer, and returns only a compact verdict. The
raw diff must not enter your context.

Scope/flags: $ARGUMENTS

Do this:
1. Run `agy-review --dir <repo-root> $ARGUMENTS`. Default scope is all staged and
   unstaged tracked changes relative to `HEAD`; use `--staged` for the final pre-commit
   review. Include a short `--goal` describing the original contract when it is not
   already present in `$ARGUMENTS`.
2. Read only its verdict, findings, test gaps, and proposed Conventional Commit subject.
   Never run `git diff` merely to duplicate this review. Untracked contents are excluded,
   so stage task-owned new files before the final review.
3. Run the smallest sufficient deterministic test/build/lint gate yourself. Inspect code
   only for a reported discrepancy, failed gate, high-risk security/architecture change,
   or an inconclusive verdict.
4. Reconcile real findings and report the final verdict. Gemini remains a first-pass
   reviewer; its approval does not replace deterministic evidence or your accountability.
