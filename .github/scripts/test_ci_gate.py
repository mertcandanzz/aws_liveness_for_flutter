"""Regression checks for gates that can reject or accidentally admit a release."""

import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest

from ci_gate import coverage, kotlin, pana, release


class GateTest(unittest.TestCase):
    def setUp(self):
        self.output = contextlib.redirect_stdout(io.StringIO())
        self.output.__enter__()
        self.addCleanup(self.output.__exit__, None, None, None)

    def test_coverage_boundary_filters_generated_and_unrelated_sources(self):
        included = "SF:C:\\checkout\\lib\\src\\controller.dart\n"
        included += "\n".join(f"DA:{i},{int(i <= 19)}" for i in range(1, 21))
        included += "\nend_of_record\n"
        text = included + "SF:lib/src/messages.g.dart\nDA:1,0\nend_of_record\n"
        text += "SF:example/lib/main.dart\nDA:1,0\nend_of_record\n"
        coverage(text, 95)
        with self.assertRaises(ValueError):
            coverage(text.replace("DA:19,1", "DA:19,0"), 95)

    def test_empty_or_generated_only_coverage_fails(self):
        for text in ("", "SF:lib/src/messages.g.dart\nDA:1,1\nend_of_record"):
            with self.assertRaises(ValueError):
                coverage(text, 95)

    def test_pana_accepts_real_report_after_logs_but_rejects_low_or_missing_scores(self):
        report = {"scores": {"grantedPoints": 150, "maxPoints": 160}}
        text = '{"level":"INFO","message":"starting"}\n' + json.dumps(report, indent=2)
        pana(text, 150)
        with self.assertRaises(ValueError):
            pana(text, 160)
        with self.assertRaises(ValueError):
            pana('{"level":"ERROR","message":"crash"}', 150)

    def test_release_requires_exact_tag_and_rejects_malformed_version(self):
        release("name: plugin\nversion: 0.1.0\n", "v0.1.0")
        for tag in ("v0.1.1", "0.1.0", "v0.1.0/unsafe"):
            with self.assertRaises(ValueError):
                release("version: 0.1.0\n", tag)

    def test_kotlin_changes_only_the_host_plugin_and_fails_on_template_drift(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "settings.gradle.kts"
            path.write_text('id("org.jetbrains.kotlin.android") version "2.2.20" apply false\n', encoding="utf-8")
            kotlin(path, "2.1.0")
            self.assertIn('version "2.1.0"', path.read_text(encoding="utf-8"))
            path.write_text("// declaration removed", encoding="utf-8")
            with self.assertRaises(ValueError):
                kotlin(path, "2.1.0")


if __name__ == "__main__":
    unittest.main()
