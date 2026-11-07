"""Static checks for the Ultimate add-on.

- every .lua file compiles under LuaJIT (Lua 5.1 syntax)
- every file listed in Ultimate.toc exists
- every .lua file under Ultimate/ is listed in the TOC
- every XML file listed exists and is well-formed
- no accidental global assignments in add-on files (simple heuristic via setfenv sandbox)
Prints OK and exits 0 on success.
"""
import pathlib
import sys
import xml.dom.minidom

try:
    from lupa.luajit21 import LuaRuntime
except ImportError:  # pragma: no cover
    from lupa.lua51 import LuaRuntime

ROOT = pathlib.Path(__file__).resolve().parent.parent
ADDON = ROOT / "Ultimate"

# Globals the add-on is allowed to define.
ALLOWED_GLOBALS = {
    "BINDING_HEADER_ULTIMATE", "Ultimate_OnCompartmentClick", "UltimateDB", "UltimateCharDB",
    "SLASH_ULTIMATE1", "SLASH_ULTIMATE2", "Ultimate_Refresh",
}


def main():
    errors = []
    lua = LuaRuntime()
    listed = []
    for line in (ADDON / "Ultimate.toc").read_text(encoding="utf-8").splitlines():
        s = line.strip()
        if s and not s.startswith("#"):
            listed.append(s.replace("\\", "/"))
    for rel in listed:
        p = ADDON / rel
        if not p.exists():
            errors.append(f"TOC lists missing file: {rel}")
        elif rel.lower().endswith(".xml"):
            try:
                xml.dom.minidom.parse(str(p))
            except Exception as e:
                errors.append(f"bad XML {rel}: {e}")
    for p in sorted(ADDON.rglob("*.lua")):
        rel = p.relative_to(ADDON).as_posix()
        if rel not in listed:
            errors.append(f"not in TOC: {rel}")
        src = p.read_text(encoding="utf-8")
        ok, msg = lua.eval("function(src, name) local f, e = loadstring(src, name); return f ~= nil, e end")(src, rel)
        if not ok:
            errors.append(f"syntax: {msg}")
            continue
        # Global-write detection: run the chunk's top level in a sandbox that records new globals.
        sandbox_check = lua.eval("""
        function(src, name, allowed)
          local f = loadstring(src, name)
          local written = {}
          local any
          any = setmetatable({}, { __index = function() return any end, __call = function() return any end,
            __newindex = function() end, __concat = function() return "" end })
          local env = setmetatable({}, {
            __index = function(_, k) local v = rawget(_G, k); if v ~= nil and type(v) ~= "function" and type(v) ~= "table" then return v end; return v or any end,
            __newindex = function(t, k, v) written[#written + 1] = k; rawset(t, k, v) end,
          })
          setfenv(f, env)
          pcall(f, "Ultimate", setmetatable({}, { __index = function(t, k) local v = setmetatable({}, getmetatable(t)); rawset(t, k, v); return v end }))
          local bad = {}
          for _, k in ipairs(written) do if not allowed[k] and not tostring(k):match("^BINDING_NAME_") and not tostring(k):match("^SLASH_") then bad[#bad + 1] = k end end
          return table.concat(bad, ",")
        end""")
        allowed = lua.table_from({k: True for k in ALLOWED_GLOBALS})
        bad = sandbox_check(src, rel, allowed)
        if bad:
            errors.append(f"{rel}: writes globals: {bad}")
    if (ADDON / "Bindings.xml").exists():
        try:
            xml.dom.minidom.parse(str(ADDON / "Bindings.xml"))
        except Exception as e:
            errors.append(f"bad Bindings.xml: {e}")
    for e in errors:
        print("ERROR", e)
    if errors:
        sys.exit(1)
    print("OK")


if __name__ == "__main__":
    main()
