"""Regenerate Ultimate/Data/FlightTimes.lua from RestedXP's Forever flight table.

Source: RXPGuides/DB/forever/flightData.lua (RestedXP Guides, CC BY-NC-SA 4.0).
The generated file stays under that license; see its header.
Usage:
  python scripts/import_flight_times.py --latest   download RestedXP's current file from GitHub
  python scripts/import_flight_times.py <path to RXPGuides/DB/forever/flightData.lua>
"""
import json
import pathlib
import sys
import urllib.request

try:
    from lupa.luajit21 import LuaRuntime
except ImportError:  # pragma: no cover
    from lupa.lua51 import LuaRuntime

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "Ultimate" / "Data" / "FlightTimes.lua"
REPO = "RestedXP/RXPGuides"
PATH = "DB/forever/flightData.lua"
RAW = f"https://raw.githubusercontent.com/{REPO}/main/{PATH}"
COMMITS = f"https://api.github.com/repos/{REPO}/commits?path={PATH}&per_page=1"

HEADER = """local ADDON, ns = ...

-- Flight times on WoW Forever, in seconds: [faction][from node ID][to node ID].
-- Node IDs are C_TaxiMap's nodeID. A flight you take yourself replaces these (see
-- Modules/FlightTimes.lua).
--
-- Data from RestedXP Guides (RXPGuides/DB/forever/flightData.lua), https://www.restedxp.com,
-- licensed CC BY-NC-SA 4.0 (https://creativecommons.org/licenses/by-nc-sa/4.0/). Converted to
-- this layout by scripts/import_flight_times.py; this file is shared under the same license.
"""


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Ultimate-addon-data-import"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8")


def latest():
    """RestedXP's current file, and a line naming the commit it came from."""
    code = fetch(RAW)
    note = ""
    try:
        commit = json.loads(fetch(COMMITS))[0]
        note = f"-- Source commit {commit['sha'][:12]} ({commit['commit']['committer']['date']}).\n"
    except Exception:  # the commit note is a nicety; the data is what matters
        pass
    return code, note


def load(code):
    """Run the data file in an empty sandbox: it only builds a table."""
    lua = LuaRuntime(unpack_returned_tuples=True)
    run = lua.eval("""function(code)
      local f = assert(loadstring(code))
      local env = { pairs = pairs, ipairs = ipairs, type = type, next = next, select = select,
        tonumber = tonumber, tostring = tostring, math = math, string = string, table = table }
      setfenv(f, env)
      local addon = { game = 'FOREVER' }
      f(nil, addon)
      return addon.FPDB
    end""")
    return run(code)


def main(code, note=""):
    fpdb = load(code)
    out = [HEADER, note, "ns.FlightTimesData = {\n"]
    for faction in ("Alliance", "Horde"):
        nodes = fpdb[faction]
        if nodes is None:
            continue
        out.append(f"  {faction} = {{\n")
        for src_id in sorted(k for k in nodes.keys() if isinstance(k, int)):
            row = nodes[src_id]
            name = row["name"]
            dests = sorted((k, row[k]) for k in row.keys() if isinstance(k, int))
            if name:
                out.append(f"    -- {name}\n")
            cells = ", ".join(f"[{d}] = {int(t)}" for d, t in dests)
            out.append(f"    [{src_id}] = {{ {cells} }},\n")
        out.append("  },\n")
    out.append("}\n")
    OUT.write_text("".join(out), encoding="utf-8", newline="\n")
    print(f"wrote {OUT}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    if sys.argv[1] == "--latest":
        main(*latest())
    else:
        main(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
