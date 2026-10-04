#!/usr/bin/env python3
"""Compare cumulative CPU of processes present in both ps snapshots."""
import pathlib
import sys


def read(path):
    result = {}
    for line in pathlib.Path(path).read_text().splitlines():
        pid, time = line.split()
        days = 0
        if "-" in time:
            day, time = time.split("-", 1)
            days = int(day)
        seconds = 0.0
        for part in time.split(":"):
            seconds = seconds * 60 + float(part)
        result[pid] = seconds + days * 86400
    return result


before, after = map(read, sys.argv[1:3])
delta = sum(max(0, value - before[pid]) for pid, value in after.items() if pid in before)
print(f"{delta / float(sys.argv[3]) * 100:.2f}")
