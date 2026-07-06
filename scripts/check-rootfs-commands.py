#!/usr/bin/env python3
import argparse
import gzip
import json
import sys
from pathlib import Path

DEFAULT_COMMANDS = [
    "adduser", "awk", "base64", "bc", "bzip2", "bunzip2", "bzcat", "cat",
    "chmod", "chown", "file", "find", "grep", "gzip", "gunzip", "head",
    "ls", "md5sum", "mkdir", "mv", "passwd", "rm", "seq", "sha256sum",
    "sort", "strings", "su", "tail", "tar", "tr", "uniq", "xxd", "xz",
    "unxz", "lzma", "unlzma",
]

def align4(value):
    return (value + 3) & ~3

def iter_newc(blob):
    pos = 0
    while pos + 110 <= len(blob):
        header = blob[pos:pos + 110]
        if header[:6] != b"070701":
            raise ValueError(f"Bad cpio newc magic at offset {pos}")
        fields = [int(header[i:i + 8], 16) for i in range(6, 110, 8)]
        size = fields[6]
        namesize = fields[11]
        pos += 110
        name = blob[pos:pos + namesize - 1].decode("utf-8", "replace")
        pos += namesize
        pos = align4(pos)
        data = blob[pos:pos + size]
        pos += size
        pos = align4(pos)
        if name == "TRAILER!!!":
            break
        yield name, fields[1], data

def load_entries(rootfs):
    with gzip.open(rootfs, "rb") as fh:
        return list(iter_newc(fh.read()))

def command_locations(entries, commands):
    names = {name for name, mode, data in entries}
    result = {}
    for command in commands:
        candidates = [
            f"bin/{command}", f"sbin/{command}",
            f"usr/bin/{command}", f"usr/sbin/{command}",
        ]
        result[command] = [candidate for candidate in candidates if candidate in names]
    return result

def main():
    parser = argparse.ArgumentParser(description="Check command availability in a gzipped cpio newc rootfs.")
    parser.add_argument("rootfs", help="Path to rootfs.cpio.gz")
    parser.add_argument("--commands", nargs="*", default=DEFAULT_COMMANDS, help="Commands to check")
    parser.add_argument("--json", action="store_true", help="Emit JSON")
    args = parser.parse_args()

    locations = command_locations(load_entries(Path(args.rootfs)), args.commands)
    missing = [cmd for cmd, paths in locations.items() if not paths]

    if args.json:
        print(json.dumps({"locations": locations, "missing": missing}, indent=2))
    else:
        for cmd in args.commands:
            paths = locations[cmd]
            print(f"{cmd}: {', '.join(paths) if paths else 'MISSING'}")

    return 1 if missing else 0

if __name__ == "__main__":
    sys.exit(main())
