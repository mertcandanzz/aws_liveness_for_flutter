"""Small, dependency-free CI gates. Run from the repository root."""

import argparse
import json
import os
from pathlib import Path
import re


def coverage(text, minimum):
    lines = {}
    source = None
    for row in text.splitlines():
        if row.startswith("SF:"):
            path = row[3:].replace("\\", "/")
            match = re.search(r"(?:^|/)lib/src/(.+)$", path)
            source = match.group(1) if match else None
            if source == "messages.g.dart":
                source = None
        elif row.startswith("DA:") and source:
            number, hits, *_ = row[3:].split(",")
            key = (source, int(number))
            lines[key] = lines.get(key, 0) + int(hits)
        elif row == "end_of_record":
            source = None
    if not lines:
        raise ValueError("No lib/src coverage records (excluding messages.g.dart)")
    hit = sum(count > 0 for count in lines.values())
    percent = 100 * hit / len(lines)
    print(f"lib/src: {hit}/{len(lines)} lines = {percent:.2f}% (minimum {minimum}%)")
    if percent < minimum:
        raise ValueError("Line coverage is below the required minimum")


def pana(text, minimum):
    # --json emits structured log lines before the final pretty-printed report.
    reports = []
    decoder = json.JSONDecoder()
    for match in re.finditer(r"(?m)^\s*\{", text):
        try:
            report, _ = decoder.raw_decode(text[match.start():].lstrip())
            if isinstance(report, dict) and "scores" in report:
                reports.append(report)
        except json.JSONDecodeError:
            pass
    if not reports:
        raise ValueError("pana did not produce a score report")
    scores = reports[-1]["scores"]
    print(f"pana: {scores['grantedPoints']}/{scores['maxPoints']} (minimum {minimum})")
    if scores["grantedPoints"] < minimum:
        raise ValueError("pana score is below the required minimum")


def release(pubspec, tag):
    match = re.search(r"(?m)^version:\s*([^\s#]+)", pubspec)
    if not match or tag != "v" + match.group(1):
        raise ValueError("Tag must be v<pubspec.yaml version>")
    if not re.fullmatch(r"v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?", tag):
        raise ValueError("Invalid version tag")
    print(f"Release version matches: {tag}")


def kotlin(path, version):
    if not re.fullmatch(r"2\.(1|2)\.\d+", version):
        raise ValueError("Expected a supported Kotlin 2.1.x or 2.2.x version")
    text = path.read_text(encoding="utf-8")
    text, count = re.subn(
        r'(id\("org.jetbrains.kotlin.android"\) version ")[^"]+(" apply false)',
        lambda match: match[1] + version + match[2],
        text,
    )
    if count != 1:
        raise ValueError("Expected exactly one host Kotlin version declaration")
    path.write_text(text, encoding="utf-8")
    print(f"Host Kotlin set to {version}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("gate", choices=["coverage", "pana", "release", "kotlin"])
    parser.add_argument("file", type=Path)
    parser.add_argument("value", nargs="?")
    args = parser.parse_args()
    if args.gate == "coverage":
        coverage(args.file.read_text(encoding="utf-8"), float(os.environ.get("COVERAGE_MIN", "95")))
    elif args.gate == "pana":
        pana(args.file.read_text(encoding="utf-8"), int(os.environ.get("PANA_MIN_SCORE", "150")))
    elif args.gate == "release":
        release(args.file.read_text(encoding="utf-8"), os.environ["GITHUB_REF_NAME"])
    elif args.gate == "kotlin":
        kotlin(args.file, args.value or "")


if __name__ == "__main__":
    main()
