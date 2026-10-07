#!/usr/bin/env python3
"""Check deduplicated Swift diagnostics against the reviewed app baseline."""
import collections
import json
import pathlib
import re
import sys

DIAGNOSTIC = re.compile(r"^(?:.*?/)?Sources/(MenoCore|Meno)/([^:]+):(\d+):\d+: warning: (.*)$", re.M)


def diagnostics(log):
    return set((module + "/" + file, int(line), message)
               for module, file, line, message in DIAGNOSTIC.findall(log))


def check(log, baseline):
    rows = diagnostics(log)
    core = [row for row in rows if row[0].startswith("MenoCore/")]
    app = [row for row in rows if row[0].startswith("Meno/")
           and re.search(r"Sendable|concurren|actor|data race", row[2], re.I)]
    locations = collections.Counter(file + ":" + str(line) for file, line, _ in app)
    new = [location for location, count in locations.items()
           if count > baseline["locations"].get(location, 0)]
    errors = []
    if core:
        errors.append(f"MenoCore has {len(core)} warnings; it must have none.")
    if len(app) > baseline["appWarningLimit"] or new:
        errors.append("App concurrency warnings exceed the reviewed baseline: " + ", ".join(sorted(new)))
    return core, app, errors


if __name__ == "__main__":
    baseline = json.loads(pathlib.Path(sys.argv[2]).read_text())
    core, app, errors = check(pathlib.Path(sys.argv[1]).read_text(), baseline)
    report = (f"MenoCore warnings: {len(core)} (required: 0)\n"
              f"App concurrency warnings: {len(app)} (limit: {baseline['appWarningLimit']})\n")
    print(report, end="")
    for file, line, message in sorted(core + app):
        print(f"{file}:{line}: {message}")
    if len(sys.argv) > 3:
        with open(sys.argv[3], "a") as summary:
            summary.write("### Strict concurrency\n\n```text\n" + report + "```\n")
    for error in errors:
        print(error, file=sys.stderr)
    sys.exit(bool(errors))
