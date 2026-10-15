#!/usr/bin/env python3
"""Compare metadata generated for an isolated SwiftPM and native Xcode fixture."""
import argparse
import json
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile


def invoke(output, name, command, cwd, timeout=600):
    record = {"command": command}
    with (output / (name + ".log")).open("w") as log:
        try:
            result = subprocess.run(command, cwd=cwd, stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
            record["exit_code"] = result.returncode
        except subprocess.TimeoutExpired:
            record["timed_out"] = True
        except OSError as error:
            record["error"] = str(error)
    return record


def inspect(metadata):
    try:
        data = json.loads((metadata / "extract.actionsdata").read_text())
        return ("MetadataProbeIntent" in data["actions"] and
                any(item.get("actionIdentifier") == "MetadataProbeIntent" and item.get("phraseTemplates")
                    for item in data.get("autoShortcuts", [])))
    except (OSError, ValueError, KeyError, TypeError):
        return False


def probe(output, generator):
    output.mkdir(parents=True, exist_ok=True)
    output = output.resolve()
    report = {"commands": {}, "swiftpm_metadata": False, "native_metadata": False,
              "swiftpm_explicit_constants_metadata": False}
    commands = report["commands"]
    fixture = Path(__file__).with_name("fixtures") / "app-intents-probe"
    try:
        with tempfile.TemporaryDirectory(prefix="meno-intents-probe-") as temporary:
            work = Path(temporary)
            source = work / "fixture"
            shutil.copytree(fixture, source)
            for name, command in (("xcode", ["xcodebuild", "-version"]), ("swift", ["swift", "--version"]),
                                  ("extractor-help", ["xcrun", "appintentsmetadataprocessor", "--help"])):
                commands[name] = invoke(output, name, command, source, timeout=30)
            spm = ["swift", "build", "--scratch-path", str(work / "spm"), "-c", "release", "--product", "MenoIntentProbe"]
            commands["spm-build"] = invoke(output, "spm-build", spm, source)
            if commands["spm-build"].get("exit_code") == 0:
                binary = subprocess.check_output([*spm, "--show-bin-path"], cwd=source, text=True, timeout=30).strip()
                sdk = subprocess.check_output(["xcrun", "--show-sdk-path"], text=True, timeout=30).strip()
                developer = subprocess.check_output(["xcode-select", "-p"], text=True, timeout=30).strip()
                version = subprocess.check_output(["xcodebuild", "-version"], text=True, timeout=30).splitlines()[-1].split()[-1]
                sources = work / "sources.txt"
                sources.write_text("".join(str(path) + "\n" for path in sorted((source / "Sources").glob("*.swift"))))
                constants = sorted((work / "spm").rglob("*.swiftconstvalues"))
                constant_list = work / "constants.txt"
                constant_list.write_text("".join(str(path) + "\n" for path in constants))
                report["swiftpm_constant_files"] = len(constants)
                destination = output / "swiftpm"
                destination.mkdir()
                command = ["xcrun", "appintentsmetadataprocessor", "--module-name", "MenoIntentProbe",
                           "--binary-file", str(Path(binary) / "MenoIntentProbe"), "--output", str(destination),
                           "--sdk-root", sdk, "--platform-family", "macOS", "--deployment-target", "14.0",
                           "--target-triple", platform.machine() + "-apple-macos14.0",
                           "--bundle-identifier", "io.github.whrss9527.meno.metadata-probe",
                           "--source-file-list", str(sources), "--swift-const-vals-list", str(constant_list),
                           "--xcode-version", version,
                           "--toolchain-dir", str(Path(developer) / "Toolchains/XcodeDefault.xctoolchain")]
                commands["spm-extract"] = invoke(output, "spm-extract", command, source, timeout=90)
                report["swiftpm_metadata"] = inspect(destination / "Metadata.appintents")
            commands["generate"] = invoke(output, "generate", [str(generator), "generate"], source, timeout=30)
            native = ["xcodebuild", "build", "-project", "MenoIntentProbe.xcodeproj", "-scheme", "MenoIntentProbe",
                      "-configuration", "Release", "-derivedDataPath", str(work / "native"),
                      "CODE_SIGNING_ALLOWED=NO", "ONLY_ACTIVE_ARCH=YES"]
            commands["native-build"] = invoke(output, "native-build", native, source)
            metadata = work / "native/Build/Products/Release/MenoIntentProbe.app/Contents/Resources/Metadata.appintents"
            report["native_metadata"] = inspect(metadata)
            if metadata.is_dir():
                shutil.copytree(metadata, output / "native/Metadata.appintents")
            # Use the selected SDK's real compiler contract, not a guessed list of protocols.
            contracts = sorted((work / "native").rglob("MenoIntentProbe_const_extract_protocols.json"))
            report["native_constant_contract_files"] = len(contracts)
            if (report["native_metadata"] and contracts and
                    commands["spm-build"].get("exit_code") == 0):
                contract = output / "native-constant-protocols.json"
                shutil.copyfile(contracts[0], contract)
                explicit_scratch = work / "spm-explicit"
                explicit_build = spm.copy()
                explicit_build[explicit_build.index("--scratch-path") + 1] = str(explicit_scratch)
                explicit_build += ["-Xswiftc", "-emit-const-values", "-Xswiftc", "-Xfrontend",
                                   "-Xswiftc", "-const-gather-protocols-file", "-Xswiftc", "-Xfrontend",
                                   "-Xswiftc", str(contract)]
                commands["spm-explicit-build"] = invoke(output, "spm-explicit-build", explicit_build, source)
                if commands["spm-explicit-build"].get("exit_code") == 0:
                    explicit_constants = sorted(explicit_scratch.rglob("*.swiftconstvalues"))
                    report["swiftpm_explicit_constant_files"] = len(explicit_constants)
                    explicit_list = work / "explicit-constants.txt"
                    explicit_list.write_text("".join(str(path) + "\n" for path in explicit_constants))
                    explicit_output = output / "swiftpm-explicit"
                    explicit_output.mkdir()
                    explicit_command = command.copy()
                    for option, value in {
                        "--binary-file": explicit_scratch / Path(binary).relative_to(work / "spm") / "MenoIntentProbe",
                        "--output": explicit_output,
                        "--swift-const-vals-list": explicit_list,
                    }.items():
                        explicit_command[explicit_command.index(option) + 1] = str(value)
                    explicit_command.append("--compile-time-extraction")
                    commands["spm-explicit-extract"] = invoke(output, "spm-explicit-extract", explicit_command, source, timeout=90)
                    report["swiftpm_explicit_constants_metadata"] = inspect(explicit_output / "Metadata.appintents")
    finally:
        (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    if (commands["native-build"].get("exit_code") != 0 or not report["native_metadata"] or
            not report["swiftpm_explicit_constants_metadata"]):
        raise SystemExit("Native or explicit SwiftPM metadata missing; inspect preserved logs before choosing a build path")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--xcodegen", type=Path, required=True)
    args = parser.parse_args()
    probe(args.output, args.xcodegen.resolve())
