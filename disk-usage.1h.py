#!/usr/bin/env python3
# <xbar.title>Mounted Disks Usage</xbar.title>
# <xbar.version>v2.0</xbar.version>
# <xbar.author>Agent Mode</xbar.author>
# <xbar.desc>Shows mounted disks with a clean, macOS-like layout. Uses SF Symbols and aligned columns, refreshes hourly.</xbar.desc>
# <xbar.dependencies>python3</xbar.dependencies>
# <xbar.abouturl>https://github.com/swiftbar/SwiftBar</xbar.abouturl>

import subprocess
import sys
import shutil
import os
import plistlib
from typing import List, Tuple
from urllib.parse import quote as urlquote

# Visual constants
BAR_WIDTH = 12
FONT = "Menlo"
FONT_SIZE = 12
NEUTRAL = "#8E8E93"  # system gray
GREEN = "#34C759"
ORANGE = "#FF9500"
RED = "#FF3B30"


def run_df() -> List[str]:
    try:
        out = subprocess.check_output([
            shutil.which("df") or "df", "-kP"
        ], text=True)
        return out.strip().splitlines()
    except Exception:
        return []


def parse_df(lines: List[str]) -> List[Tuple[str, int, int, int]]:
    # Returns list of (mountpoint, total_k, used_k, avail_k)
    out = []
    if not lines:
        return out
    header_skipped = False
    for line in lines:
        if not header_skipped:
            header_skipped = True
            continue
        if not line.strip():
            continue
        parts = line.split()
        if len(parts) < 6:
            continue
        fs = parts[0]
        try:
            total_k = int(parts[1])
            used_k = int(parts[2])
            avail_k = int(parts[3])
        except ValueError:
            continue
        mountpoint = parts[5] if len(parts) == 6 else " ".join(parts[5:])
        if not fs.startswith("/dev/"):
            continue
        if total_k <= 0:
            continue
        out.append((mountpoint, total_k, used_k, avail_k))
    seen = set()
    uniq = []
    for m in out:
        if m[0] in seen:
            continue
        seen.add(m[0])
        uniq.append(m)
    uniq.sort(key=lambda x: x[0].lower())
    return uniq


def kb_to_gb(kb: int) -> float:
    return kb / 1024.0 / 1024.0


def fmt_gb(gb: float) -> str:
    v = 0.0 if abs(gb) < 0.05 else gb
    return f"{v:.1f}G"


def pct(used_k: int, total_k: int) -> int:
    if total_k <= 0:
        return 0
    return int(round(min(1.0, max(0.0, used_k / float(total_k))) * 100))


def status_color(used_pct: int) -> str:
    if used_pct >= 90:
        return RED
    if used_pct >= 70:
        return ORANGE
    return GREEN


def unicode_bar(used_k: int, total_k: int) -> str:
    if total_k <= 0:
        return ""
    frac = min(1.0, max(0.0, used_k / float(total_k)))
    used_units = int(round(frac * BAR_WIDTH))
    free_units = BAR_WIDTH - used_units
    return ("█" * used_units) + ("░" * free_units)


def vol_name_for_mount(mountpoint: str) -> str:
    # Try to get the display name via diskutil; fallback to basename
    try:
        out = subprocess.check_output([
            shutil.which("diskutil") or "diskutil", "info", "-plist", mountpoint
        ])
        data = plistlib.loads(out)
        name = data.get("VolumeName") or data.get("MediaName")
        if isinstance(name, bytes):
            name = name.decode("utf-8", "ignore")
        if name:
            return str(name)
    except Exception:
        pass
    base = mountpoint if mountpoint != "/" else "Macintosh HD"
    return os.path.basename(base.rstrip("/")) or base


def main():
    lines = run_df()
    entries = parse_df(lines)

    total_all = sum(t for _, t, _, _ in entries)
    used_all = sum(u for _, _, u, _ in entries)
    overall_pct = pct(used_all, total_all) if total_all else 0

    # Menu bar title with SF Symbol
    print(f"Disks {overall_pct}% | sfimage=internaldrive.fill")
    print("---")

    if not entries:
        print("No mounted disks found | color=#666666")
        return

    # Header
    header = f"{'Volume':<18} {'Bar':<{BAR_WIDTH}}  {'Used%':>5}   {'Free':>7}  {'Total':>7}"
    print(f"{header} | font={FONT} size={FONT_SIZE} color={NEUTRAL}")
    print("---")

    for mountpoint, total_k, used_k, avail_k in entries:
        name = vol_name_for_mount(mountpoint)
        total_g = kb_to_gb(total_k)
        used_pct = pct(used_k, total_k)
        free_g = kb_to_gb(avail_k)
        bar = unicode_bar(used_k, total_k)
        sc = status_color(used_pct)
        # Align
        name_col = (name[:18] + ("…" if len(name) > 18 else "")).ljust(18)
        used_col = f"{used_pct:>3}%"
        free_col = f"{fmt_gb(free_g):>7}"
        total_col = f"{fmt_gb(total_g):>7}"
        href = f"file://{urlquote(mountpoint)}"
        line = f"{name_col} {bar:<{BAR_WIDTH}}  {used_col:>5}   {free_col}  {total_col} | font={FONT} size={FONT_SIZE} href={href} sfimage=externaldrive sfcolor={sc}"
        print(line)
        # Submenu actions
        print(f"--Open {name} | href={href} sfimage=folder")
        print(f"--Reveal in Finder | bash=open param1=-R param2={urlquote(mountpoint)} terminal=false")
        print(f"--Eject (unmount) | bash=diskutil param1=unmount param2={urlquote(mountpoint)} refresh=true terminal=false")


if __name__ == "__main__":
    sys.exit(main())
