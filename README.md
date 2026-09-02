<div align="center">

# 🛰️ Antigravity for Claude Code On Windows

**Run the Antigravity CLI (Gemini) as a collaborating sub-agent, right inside Claude Code.**
![Antigravity for Claude Code — Claude directs, Gemini executes](docs/hero.png)
Claude conducts the judgement; Gemini does the heavy lifting — intelligent model routing across the SDLC.

</div>

---

## What this repository does

This Claude Code plugin delegates suitable tasks to the Antigravity CLI (`agy`), allowing Gemini to work as a sub-agent while Claude remains the main orchestrator and reviews the result.

This fork adds reliable native Windows support through Windows ConPTY and [`agy-headless-bridge`](https://github.com/rhishi99/agy-headless-bridge). WSL is not required, and the bridge repository is used without modification.

## Requirements

- Native Windows supported through [`agy-headless-bridge`](https://github.com/rhishi99/agy-headless-bridge); follow its Windows prerequisites
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- [Antigravity CLI](https://antigravity.google/docs/cli-using) (`agy`), installed and authenticated
- Python 3.9 or newer
- Git Bash, normally provided by [Git for Windows](https://git-scm.com/download/win), because this plugin's wrappers and hooks are Bash scripts

Claude Code itself can run without Git for Windows by using PowerShell. This plugin currently needs Git Bash; Git is not otherwise required by its runtime.

Run `agy` once and complete its authentication before installing the plugin. Confirm that Gemini models are available with:

```powershell
agy models
```

## Installation

Install the unchanged Windows ConPTY bridge:

```powershell
py -3 -m pip install -U agy-headless-bridge
```

Then install this repository as a Claude Code plugin. Run these commands inside Claude Code:

```text
/plugin marketplace add GryAsl/antigravity-for-claude-code-Windows-ConPTY
/plugin install antigravity@antigravity-for-claude-code-windows-conpty
/antigravity:setup
```

The setup command checks Claude Code, `agy`, Python, the bridge package, ConPTY support, authentication, and configured Gemini models.

## Usage

Claude Code can select the included `antigravity-delegate` sub-agent automatically for suitable work. You can also delegate explicitly:

```text
/antigravity:delegate "Inspect this project and summarize its architecture"
/antigravity:delegate --tier flash "Implement the tests for this module"
/antigravity:review
/antigravity:research "Research this topic and include sources"
```

For lean repository exploration and diff review, Claude can call the included wrappers
directly:

```text
agy-scout --dir "C:\path\to\repo" "Trace the request flow and identify likely hotspots"
agy-review --dir "C:\path\to\repo" --staged --goal "Implement feature X without behavior regressions"
```

`agy-scout` builds the repeated read-only Flash contract automatically. `agy-review`
sends the Git patch directly to a fresh Gemini Flash verifier and returns only a compact
verdict plus a proposed Conventional Commit subject; the raw diff does not enter Claude's
context. Windows-safe chunks are reconciled internally without exposing partial output.
Untracked contents are excluded until staged, and patches over 48 KiB must be narrowed
with `--path` or reviewed as staged logical groups.

For tasks that modify files, work on a separate Git branch and review the resulting diff. Use `--yolo` only when necessary: it grants Antigravity broad tool permissions.

To force `--yolo` for every plugin delegation on a trusted machine, set
`AGY_ALWAYS_YOLO=1` in Claude Code's user-level `env` settings. The equivalent plugin
option is `always_yolo=on`. This automatically adds `--dangerously-skip-permissions` to
`agy-delegate`, `agy-scout`, and `agy-review`; it grants access beyond `--dir`, including
other readable/writable files, commands, network, and process-visible credentials.

On native Windows, long structured/agentic calls may produce no intermediate output.
The wrapper therefore derives its ConPTY idle limit from the task's hard timeout instead
of killing every silent call after 120 seconds. Override it only when needed with
`--idle-timeout <seconds>` or the plugin's `idle_timeout` setting.

If something fails, run `/antigravity:setup` again and see [Windows troubleshooting](docs/TROUBLESHOOTING.md).

## License

[MIT](LICENSE). This is a community project and is not affiliated with Google or Anthropic.
