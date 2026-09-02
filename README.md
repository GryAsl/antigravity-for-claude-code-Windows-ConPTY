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

- Windows 10 or Windows 11 with ConPTY support
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- [Antigravity CLI](https://antigravity.google/docs/cli-using) (`agy`), installed and authenticated
- Python 3.9 or newer
- [Git for Windows](https://git-scm.com/download/win)

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

For tasks that modify files, work on a separate Git branch and review the resulting diff. Use `--yolo` only when necessary: it grants Antigravity broad tool permissions.

If something fails, run `/antigravity:setup` again and see [Windows troubleshooting](docs/TROUBLESHOOTING.md).

## License

[MIT](LICENSE). This is a community project and is not affiliated with Google or Anthropic.
