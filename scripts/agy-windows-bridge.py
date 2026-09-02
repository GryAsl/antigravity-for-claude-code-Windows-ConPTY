#!/usr/bin/env python3
"""Native-Windows adapter between agy-delegate.sh and agy-headless-bridge.

The Bash wrapper owns orchestration, tier routing, and error classification. This
module only validates one UTF-8 JSON request, invokes the installed bridge package,
and preserves the wrapper's stdout/stderr/exit-code contract as far as the bridge
API permits.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any


EXIT_FAILED = 2
EXIT_EMPTY = 3
EXIT_TIMEOUT = 12
EXIT_AGY_MISSING = 13
EXIT_BRIDGE_MISSING = 16

_RESERVED_EXTRA_ARGS = {
    "-p",
    "--print",
    "--prompt",
    "--model",
    "--add-dir",
    "--print-timeout",
}


def _configure_stdio() -> None:
    """Keep non-ASCII prompts and diagnostics stable on Windows locales."""
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if reconfigure is not None:
            reconfigure(encoding="utf-8", errors="replace")


def _fail(kind: str, message: str, code: int) -> int:
    one_line = " ".join(message.split())
    sys.stderr.write(f"AGY_BRIDGE_ERROR {kind}: {one_line}\n")
    return code


def _positive_number(value: Any, field: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{field} must be a number")
    number = float(value)
    if number <= 0:
        raise ValueError(f"{field} must be greater than zero")
    return number


def _string_list(value: Any, field: str) -> list[str]:
    if value is None:
        return []
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise ValueError(f"{field} must be an array of strings")
    return value


def load_request(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"cannot read request JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise ValueError("request JSON must be an object")

    prompt = data.get("prompt")
    if not isinstance(prompt, str) or not prompt.strip():
        raise ValueError("prompt must be a non-empty string")

    model = data.get("model")
    if model is not None and not isinstance(model, str):
        raise ValueError("model must be a string or null")

    agy_path = data.get("agy_path")
    if agy_path is not None and not isinstance(agy_path, str):
        raise ValueError("agy_path must be a string or null")

    add_dirs = _string_list(data.get("add_dirs"), "add_dirs")
    extra_args = _string_list(data.get("extra_args"), "extra_args")
    forbidden = [arg for arg in extra_args if arg in _RESERVED_EXTRA_ARGS]
    if forbidden:
        raise ValueError(
            "extra_args contains bridge-owned flag(s): " + ", ".join(forbidden)
        )

    structured = data.get("structured_output", False)
    if not isinstance(structured, bool):
        raise ValueError("structured_output must be a boolean")

    return {
        "prompt": prompt,
        "model": model or None,
        "agy_path": agy_path or None,
        "add_dirs": add_dirs,
        "extra_args": extra_args,
        "timeout": _positive_number(data.get("timeout", 900), "timeout"),
        "idle_timeout": _positive_number(
            data.get("idle_timeout", 120), "idle_timeout"
        ),
        "structured_output": structured,
    }


def extract_structured_envelope(raw: str) -> str:
    """Return a JSON envelope even if a PTY added harmless surrounding text.

    agy 1.1.8 emitted raw newlines inside JSON strings, hence strict=False. If no
    credible envelope can be decoded, return the untouched output and let the Bash
    wrapper's existing fallback/error handling decide what it means.
    """
    decoder = json.JSONDecoder(strict=False)
    for index, char in enumerate(raw):
        if char != "{":
            continue
        try:
            value, _ = decoder.raw_decode(raw, index)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict) and any(
            key in value for key in ("status", "response", "error", "usage")
        ):
            return json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    return raw


def main(argv: list[str] | None = None) -> int:
    _configure_stdio()
    args = list(sys.argv[1:] if argv is None else argv)
    if len(args) != 1:
        return _fail("BAD_REQUEST", "usage: agy-windows-bridge.py REQUEST.json", 1)

    try:
        request = load_request(Path(args[0]))
    except ValueError as exc:
        return _fail("BAD_REQUEST", str(exc), 1)

    try:
        from agy_headless_bridge import AgyNotFoundError, AgyTimeoutError, run
    except (ImportError, ModuleNotFoundError) as exc:
        return _fail(
            "PACKAGE_MISSING",
            f"agy-headless-bridge is not importable by {sys.executable}: {exc}",
            EXIT_BRIDGE_MISSING,
        )

    try:
        output = run(
            request["prompt"],
            timeout=request["timeout"],
            idle_timeout=request["idle_timeout"],
            agy_path=request["agy_path"],
            add_dirs=request["add_dirs"],
            model=request["model"],
            extra_args=request["extra_args"],
        )
    except AgyNotFoundError as exc:
        return _fail("AGY_MISSING", str(exc), EXIT_AGY_MISSING)
    except AgyTimeoutError as exc:
        partial = getattr(exc, "partial", "") or ""
        if partial:
            sys.stdout.write(partial)
            if not partial.endswith("\n"):
                sys.stdout.write("\n")
        return _fail("TIMEOUT", str(exc), EXIT_TIMEOUT)
    except Exception as exc:  # bridge/backend failures must remain actionable
        message = f"{type(exc).__name__}: {exc}"
        if "pywinpty" in message.lower() or "winpty" in message.lower():
            return _fail("PACKAGE_MISSING", message, EXIT_BRIDGE_MISSING)
        return _fail("FAILED", message, EXIT_FAILED)

    if not output or not output.strip():
        return _fail("EMPTY_OUTPUT", "agy returned no output through ConPTY", EXIT_EMPTY)

    if request["structured_output"]:
        output = extract_structured_envelope(output)
    sys.stdout.write(output)
    if not output.endswith("\n"):
        sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
