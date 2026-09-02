#!/usr/bin/env python3
"""Dependency-free contract tests for scripts/agy-windows-bridge.py."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import sys
import tempfile
import types
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "agy_windows_bridge", ROOT / "scripts" / "agy-windows-bridge.py"
)
assert SPEC and SPEC.loader
adapter = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(adapter)


class AdapterTests(unittest.TestCase):
    def request(self, **overrides):
        data = {
            "prompt": "Türkçe: çalışıyor mu?",
            "model": "Gemini 3.7 Flash (High)",
            "add_dirs": [r"C:\repo with space"],
            "timeout": 45,
            "idle_timeout": 10,
            "structured_output": True,
            "extra_args": ["--output-format", "json"],
        }
        data.update(overrides)
        td = tempfile.TemporaryDirectory()
        path = Path(td.name) / "request.json"
        path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
        return td, path

    def test_request_round_trips_utf8_and_spaces(self):
        td, path = self.request()
        self.addCleanup(td.cleanup)
        data = adapter.load_request(path)
        self.assertEqual(data["prompt"], "Türkçe: çalışıyor mu?")
        self.assertEqual(data["add_dirs"], [r"C:\repo with space"])

    def test_bridge_owned_flags_are_rejected_from_extra_args(self):
        td, path = self.request(extra_args=["--print-timeout", "20s"])
        self.addCleanup(td.cleanup)
        with self.assertRaisesRegex(ValueError, "bridge-owned"):
            adapter.load_request(path)

    def test_structured_envelope_is_extracted_from_pty_noise(self):
        raw = 'banner\n{"status":"SUCCESS","response":"satır 1\nsatır 2"}\ntrailer'
        clean = adapter.extract_structured_envelope(raw)
        self.assertEqual(json.loads(clean, strict=False)["response"], "satır 1\nsatır 2")

    def test_main_preserves_structured_output(self):
        td, path = self.request()
        self.addCleanup(td.cleanup)
        fake = types.ModuleType("agy_headless_bridge")

        class Missing(RuntimeError):
            pass

        class TimedOut(TimeoutError):
            pass

        fake.AgyNotFoundError = Missing
        fake.AgyTimeoutError = TimedOut
        fake.run = lambda *a, **k: 'noise\n{"status":"SUCCESS","response":"OK"}'
        old = sys.modules.get("agy_headless_bridge")
        sys.modules["agy_headless_bridge"] = fake
        self.addCleanup(
            lambda: sys.modules.__setitem__("agy_headless_bridge", old)
            if old is not None
            else sys.modules.pop("agy_headless_bridge", None)
        )
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            rc = adapter.main([str(path)])
        self.assertEqual(rc, 0)
        self.assertEqual(json.loads(stdout.getvalue())["response"], "OK")
        self.assertEqual(stderr.getvalue(), "")

    def test_timeout_preserves_partial_output_and_exit_code(self):
        td, path = self.request()
        self.addCleanup(td.cleanup)
        fake = types.ModuleType("agy_headless_bridge")

        class Missing(RuntimeError):
            pass

        class TimedOut(TimeoutError):
            def __init__(self):
                super().__init__("agy idle for 10s")
                self.partial = "HALF_DONE"

        def run(*args, **kwargs):
            raise TimedOut()

        fake.AgyNotFoundError = Missing
        fake.AgyTimeoutError = TimedOut
        fake.run = run
        old = sys.modules.get("agy_headless_bridge")
        sys.modules["agy_headless_bridge"] = fake
        self.addCleanup(
            lambda: sys.modules.__setitem__("agy_headless_bridge", old)
            if old is not None
            else sys.modules.pop("agy_headless_bridge", None)
        )
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            rc = adapter.main([str(path)])
        self.assertEqual(rc, adapter.EXIT_TIMEOUT)
        self.assertIn("HALF_DONE", stdout.getvalue())
        self.assertIn("AGY_BRIDGE_ERROR TIMEOUT", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
