#!/usr/bin/env python3
"""Summarise a Yosys `stat` report (synth_xilinx) as LUT / FF / RAM per module."""
import re
import sys

mods = {}
cur = None
for line in open(sys.argv[1]):
    m = re.match(r"=== (.*) ===", line)
    if m:
        name = m.group(1)
        name = re.sub(r"^\$paramod\$?[0-9a-f]*\\?", "", name)
        name = name.split("\\")[0]
        cur = mods.setdefault(name, {"LUT": 0, "FF": 0, "LUTRAM": 0, "BRAM": 0, "CARRY4": 0})
        continue
    m = re.match(r"\s+(\w+)\s+(\d+)$", line)
    if m and cur is not None:
        cell, n = m.group(1), int(m.group(2))
        if cell.startswith("LUT"):
            cur["LUT"] += n
        elif cell.startswith("FD"):
            cur["FF"] += n
        elif cell.startswith("RAM32") or cell.startswith("RAM64") or cell.startswith("SRL"):
            cur["LUTRAM"] += n
        elif cell.startswith("RAMB"):
            cur["BRAM"] += n
        elif cell == "CARRY4":
            cur["CARRY4"] += n

print(f"{'module':<16}{'LUT':>7}{'FF':>7}{'LUTRAM':>8}{'CARRY4':>8}{'BRAM36':>8}")
for name, c in sorted(mods.items()):
    if name == "design hierarchy" or not any(c.values()):
        continue
    print(f"{name:<16}{c['LUT']:>7}{c['FF']:>7}{c['LUTRAM']:>8}{c['CARRY4']:>8}{c['BRAM']:>8}")
