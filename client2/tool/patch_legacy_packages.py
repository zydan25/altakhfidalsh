#!/usr/bin/env python3
"""Patch legacy Chewie APIs in the Pub cache for Flutter 2.2.x CI builds.

The app intentionally keeps flutter_html 1.x and its older video_player API.
Chewie 0.9.10 and chewie_audio 1.0.0+1 use Flutter APIs removed in Flutter 2.
This script applies only source-level compatibility substitutions to the resolved
Pub-cache copies; it does not modify app UI or production services.
"""
from __future__ import annotations

import os
from pathlib import Path
import sys

PACKAGE_REPLACEMENTS = {
    "chewie-0.9.10": {
        "resizeToAvoidBottomPadding:": "resizeToAvoidBottomInset:",
        "context.inheritFromWidgetOfExactType(_ChewieControllerProvider)":
            "context.dependOnInheritedWidgetOfExactType<_ChewieControllerProvider>()",
    },
    "chewie_audio-1.0.0+1": {
        "context.inheritFromWidgetOfExactType(_ChewieAudioControllerProvider)":
            "context.dependOnInheritedWidgetOfExactType<_ChewieAudioControllerProvider>()",
    },
}


def cache_roots() -> list[Path]:
    roots = []
    configured = os.environ.get("PUB_CACHE")
    if configured:
        roots.append(Path(configured).expanduser())
    roots.append(Path.home() / ".pub-cache")
    # Flutter setup actions may use a cache under the tool-cache directory.
    for env_name in ("FLUTTER_ROOT", "RUNNER_TEMP"):
        value = os.environ.get(env_name)
        if value:
            roots.append(Path(value).expanduser() / ".pub-cache")
    return list(dict.fromkeys(p.resolve() for p in roots))


def main() -> int:
    roots = cache_roots()
    errors = []
    for package_name, replacements in PACKAGE_REPLACEMENTS.items():
        package_dirs = sorted({
            p
            for root in roots
            if root.exists()
            for p in root.glob(f"hosted/*/{package_name}")
            if p.is_dir()
        })
        if not package_dirs:
            errors.append(
                f"Could not find {package_name} in Pub cache roots: "
                + ", ".join(str(root) for root in roots)
            )
            continue

        package_hits = 0
        for package_dir in package_dirs:
            for source in package_dir.rglob("*.dart"):
                try:
                    original = source.read_text(encoding="utf-8")
                except (OSError, UnicodeDecodeError):
                    continue
                updated = original
                for old, new in replacements.items():
                    updated = updated.replace(old, new)
                if updated != original:
                    source.write_text(updated, encoding="utf-8")
                    package_hits += sum(
                        original.count(old) for old in replacements
                    )
        if package_hits == 0:
            errors.append(
                f"No expected deprecated API was found in {package_name}; "
                "the resolved package source may have changed."
            )
        else:
            print(f"Patched {package_name}: {package_hits} deprecated API use(s).")

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
