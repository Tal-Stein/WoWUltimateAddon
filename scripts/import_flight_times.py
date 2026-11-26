"""Regenerate Ultimate/Data/FlightTimes.lua from RestedXP's Forever flight table.

Source: RXPGuides/DB/forever/flightData.lua (RestedXP Guides, CC BY-NC-SA 4.0).
The generated file stays under that license; see its header.
Usage: python scripts/import_flight_times.py <path to RXPGuides/DB/forever/flightData.lua>
"""
import pathlib
import sys

try:
    from lupa.luajit21 import LuaRuntime
except ImportError:  # pragma: no cover
    from lupa.lua51 import LuaRuntime

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "Ultimate" / "Data" / "FlightTimes.lua"

HEADER = """local ADDON, ns = ...

-- Flight times on WoW Forever, in seconds: [faction][from node ID][to node ID].
-- Node IDs are C_TaxiMap's nodeID. A flight you take yourself replaces these (see
-- Modules/FlightTimes.lua).
--
-- Data from RestedXP Guides (RXPGuides/DB/forever/flightData.lua), https://www.restedxp.com,
-- licensed CC BY-NC-SA 4.0 (https://creativecommons.org/licenses/by-nc-sa/4.0/). Converted to
-- this layout by scripts/import_flight_times.py; this file is shared under the same license.
ns.FlightTimesData = {
"""


def main(src):
    lua = LuaRuntime(unpack_returned_tuples=True)
    code = pathlib.Path(src).read_text(encoding="utf-8")
    load = lua.eval("function(code) local addon = { game = 'FOREVER' }; "
                    "assert(loadstring(code))(nil, addon); return addon.FPDB end")
    fpdb = load(code)
    out = [HEADER]
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
    main(sys.argv[1])
