#!/usr/bin/env python3
"""Build and inspect the real SwiftPM app's metadata using verified SDK contracts."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = {"SetMenoZenIntent": "enabled", "ApplyMenoSceneIntent": "scene"}


def inspect(metadata):
    data = json.loads((metadata / "extract.actionsdata").read_text())
    json.loads((metadata / "version.json").read_text())
    for name, parameter in EXPECTED.items():
        action = data["actions"][name]
        if action.get("openAppWhenRun") is not True:
            raise ValueError(f"{name} must start the foreground app")
        if not any(p.get("name") == parameter and p.get("isOptional") is False for p in action.get("parameters", [])):
            raise ValueError(f"{name} is missing required {parameter}")
    shortcuts = {item["actionIdentifier"] for item in data.get("autoShortcuts", []) if item.get("phraseTemplates")}
    if not set(EXPECTED) <= shortcuts:
        raise ValueError("Both discoverable AppShortcuts are required")
    return data


def inspect_app(app):
    import re
    data = inspect(app / "Contents/Resources/Metadata.appintents")
    phrases = {"Set Zen mode in ${applicationName}", "Apply a saved scene in ${applicationName}"}
    for language in ("en", "zh-Hans", "zh-Hant"):
        source = app / f"Contents/Resources/{language}.lproj/AppShortcuts.strings"
        pairs = re.findall(r'("(?:[^"\\]|\\.)*")\s*=\s*("(?:[^"\\]|\\.)*")\s*;', source.read_text())
        table = {json.loads(key): json.loads(value) for key, value in pairs}
        if set(table) != phrases or any(value.count("${applicationName}") != 1 for value in table.values()):
            raise ValueError("Missing or invalid localized shortcut phrases: " + language)
    return data


def configure(output):
    version = subprocess.check_output(["xcodebuild", "-version"], text=True, timeout=30)
    major = version.splitlines()[0].split()[1].split(".")[0]
    if major not in ("16", "26"):
        raise ValueError("Validate the selected Xcode constant-extraction contract before packaging: " + version)
    source = ROOT / f"scripts/fixtures/app-intents-protocols/xcode{major}.json"
    output.mkdir(parents=True, exist_ok=True)
    target = output / "constant-protocols.json"
    shutil.copyfile(source, target)
    (output / "configuration.json").write_text(json.dumps({"xcode": version, "protocols": json.loads(source.read_text()),
        "contract_sha256": hashlib.sha256(source.read_bytes()).hexdigest()}, indent=2) + "\n")
    print(target.resolve())


def extract(app, work, configuration, universal):
    binary = app / "Contents/MacOS/Meno"
    architectures = subprocess.check_output(["lipo", "-archs", str(binary)], text=True, timeout=30).split()
    if not set(architectures) <= {"arm64", "x86_64"} or not architectures:
        raise ValueError("Unexpected app architectures")
    if universal and set(architectures) != {"arm64", "x86_64"}:
        raise ValueError("Universal packaging must include both architectures")
    sources = work / "sources.txt"
    sources.write_text("".join(str(p) + "\n" for p in sorted((ROOT / "Sources/Meno").rglob("*.swift"))))
    sdk = subprocess.check_output(["xcrun", "--show-sdk-path"], text=True, timeout=30).strip()
    developer = subprocess.check_output(["xcode-select", "-p"], text=True, timeout=30).strip()
    xcode = subprocess.check_output(["xcodebuild", "-version"], text=True, timeout=30).splitlines()[-1].split()[-1]
    constants = sorted((ROOT / ".build").rglob("*.swiftconstvalues"))
    evidence = {}
    for architecture in architectures:
        selected = [p for p in constants if p.parent.name == "Meno.build" and p.parent.parent.name.lower() == configuration and any(
            part.startswith(architecture + "-apple-macos") for part in p.parts)]
        if not selected:
            (work / "constant-inventory.json").write_text(json.dumps([str(p.relative_to(ROOT)) for p in constants], indent=2) + "\n")
            raise ValueError("No compiled app constant values for " + architecture)
        listing = work / (architecture + "-constants.txt")
        listing.write_text("".join(str(p) + "\n" for p in selected))
        output = work / (architecture + "-metadata")
        if output.exists():
            shutil.rmtree(output)
        output.mkdir()
        command = ["xcrun", "appintentsmetadataprocessor", "--module-name", "Meno", "--binary-file", str(binary),
                   "--output", str(output), "--sdk-root", sdk, "--platform-family", "macOS", "--deployment-target", "14.0",
                   "--target-triple", architecture + "-apple-macos14.0", "--bundle-identifier", "io.github.whrss9527.meno",
                   "--source-file-list", str(sources), "--swift-const-vals-list", str(listing), "--xcode-version", xcode,
                   "--toolchain-dir", str(Path(developer) / "Toolchains/XcodeDefault.xctoolchain")]
        with (work / (architecture + "-extract.log")).open("w") as log:
            subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=120)
        inspect(output / "Metadata.appintents")
        evidence[architecture] = {"constant_files": [str(p.relative_to(ROOT)) for p in selected], "metadata_sha256": hashlib.sha256(
            (output / "Metadata.appintents/extract.actionsdata").read_bytes()).hexdigest()}
    preferred = platform.machine() if platform.machine() in architectures else architectures[0]
    destination = app / "Contents/Resources/Metadata.appintents"
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(work / (preferred + "-metadata") / "Metadata.appintents", destination)
    inspect_app(app)
    (work / "report.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print("Actual app metadata verified: " + ", ".join(architectures))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    prepare = sub.add_parser("configure")
    prepare.add_argument("output", type=Path)
    package = sub.add_parser("extract")
    package.add_argument("app", type=Path)
    package.add_argument("work", type=Path)
    package.add_argument("--configuration", choices=("debug", "release"), required=True)
    package.add_argument("--universal", action="store_true")
    check = sub.add_parser("check")
    check.add_argument("app", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "configure":
            configure(args.output.resolve())
        elif args.command == "extract":
            extract(args.app.resolve(), args.work.resolve(), args.configuration, args.universal)
        else:
            inspect_app(args.app)
    except (OSError, ValueError, KeyError, TypeError, IndexError, subprocess.SubprocessError) as error:
        parser.exit(1, "App Intents metadata failed: " + str(error) + "\n")


if __name__ == "__main__":
    main()
