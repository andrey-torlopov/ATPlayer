#!/usr/bin/env python3
"""Validate Markdown metadata and reproduce the corresponding JSON files.

Run without arguments to check that JSON files match the Markdown sources.
Run with --write to regenerate them after changing the Markdown sources.
"""

import argparse
import json
from pathlib import Path
import re
import sys


LIMITS = {
    "Name": 30,
    "Subtitle": 30,
    "Promotional Text": 170,
    "Keywords": 100,
    "Description": 4000,
    "What's New": 4000,
}
LOCALES = ("ru-RU", "en-US")


def serialize(value):
    return json.dumps(value, ensure_ascii=False, indent=2) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="Regenerate JSON outputs")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    report = {}
    outputs = {}

    for locale in LOCALES:
        source = (root / f"{locale}.md").read_text(encoding="utf-8")
        fields = {}
        report[locale] = {}
        for field, limit in LIMITS.items():
            matches = re.findall(
                r"^## " + re.escape(field) + r"\n\n(.*?)(?=\n## |\Z)",
                source,
                flags=re.MULTILINE | re.DOTALL,
            )
            if len(matches) != 1:
                raise ValueError(f"{locale}: expected exactly one {field} section")
            value = matches[0].strip()
            count = len(value)
            if not value or count > limit:
                raise ValueError(f"{locale} {field}: {count}/{limit} characters")
            if "\ufffd" in value:
                raise ValueError(f"{locale} {field}: invalid Unicode replacement character")
            utf8_count = len(value.encode("utf-8"))
            if field == "Keywords" and utf8_count > 100:
                raise ValueError(f"{locale} Keywords: {utf8_count}/100 UTF-8 bytes")
            fields[field] = value
            report[locale][field] = {
                "characters": count,
                "limit": limit,
                "formula": f"{count}/{limit}",
                "valid": True,
            }
            if field == "Keywords":
                report[locale][field]["utf8_bytes"] = utf8_count
                report[locale][field]["byte_limit"] = 100
                report[locale][field]["byte_formula"] = f"{utf8_count}/100"
        outputs[root / f"{locale}.json"] = serialize(fields)

    review_source = (root / "review-notes.md").read_text(encoding="utf-8")
    review_matches = re.findall(
        r"^## Notes to paste into App Store Connect\n\n(.*?)(?=\n## |\Z)",
        review_source,
        flags=re.MULTILINE | re.DOTALL,
    )
    if len(review_matches) != 1:
        raise ValueError("review-notes: expected exactly one paste-ready section")
    review_notes = review_matches[0].strip()
    review_bytes = len(review_notes.encode("utf-8"))
    if not review_notes or review_bytes > 4000:
        raise ValueError(f"Review Notes: {review_bytes}/4000 UTF-8 bytes")
    report["Review Notes"] = {
        "characters": len(review_notes), "utf8_bytes": review_bytes,
        "byte_limit": 4000, "formula": f"{review_bytes}/4000", "valid": True,
    }
    report["Release"] = {"version": "1.1.0", "build": "2", "status": "metadata prepared; publication not asserted"}
    report["Sources"] = [
        "https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information",
        "https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/",
        "https://developer.apple.com/app-store/app-privacy-details/",
    ]
    outputs[root / "validation.json"] = serialize(report)
    for path, expected in outputs.items():
        if args.write:
            path.write_text(expected, encoding="utf-8")
        elif not path.exists() or path.read_text(encoding="utf-8") != expected:
            raise ValueError(f"{path.name} is out of date; run validator.py --write")

    print(serialize(report), end="")
    print("All fields are within limits; generated JSON matches Markdown.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print(f"Validation failed: {error}", file=sys.stderr)
        sys.exit(1)
