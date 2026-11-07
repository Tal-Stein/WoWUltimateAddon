"""Insert files into Ultimate.toc.

Usage: python scripts/toc.py <after-or-END> <file> [<file> ...]
Paths use forward slashes on the command line; they are written with backslashes (WoW style).
Files already listed are skipped.
"""
import pathlib
import sys

TOC = pathlib.Path(__file__).resolve().parent.parent / "Ultimate" / "Ultimate.toc"


def main():
    after, files = sys.argv[1].replace("/", "\\"), [f.replace("/", "\\") for f in sys.argv[2:]]
    lines = TOC.read_text(encoding="utf-8").replace("\r\n", "\n").rstrip("\n").split("\n")
    files = [f for f in files if f not in lines]
    if after == "END":
        idx = len(lines)
    else:
        idx = lines.index(after) + 1
    lines[idx:idx] = files
    TOC.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print("added:", ", ".join(files) or "(none)")


if __name__ == "__main__":
    main()
