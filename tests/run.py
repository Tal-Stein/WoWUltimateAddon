"""Offline test runner for the Ultimate add-on.

Each tests/lua/test_*.lua file runs in a fresh LuaJIT (Lua 5.1) runtime:
  1. tests/lua/harness.lua  (assertions + WoW API stubs)
  2. every .lua file listed in Ultimate/Ultimate.toc, in order, called as chunk("Ultimate", ns)
  3. the test file itself
Usage: python tests/run.py [substring-filter]
"""
import pathlib
import sys

try:
    from lupa.luajit21 import LuaRuntime
except ImportError:  # pragma: no cover
    from lupa.lua51 import LuaRuntime

ROOT = pathlib.Path(__file__).resolve().parent.parent
ADDON = ROOT / "Ultimate"
TESTS = ROOT / "tests" / "lua"


def toc_files():
    files = []
    for line in (ADDON / "Ultimate.toc").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.lower().endswith(".lua"):
            files.append((ADDON / line.replace("\\", "/")).as_posix())
    return files


def run_file(test_path):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().ADDON_ROOT = ADDON.as_posix()
    lua.execute(f"dofile([[{(TESTS / 'harness.lua').as_posix()}]])")
    loader = lua.eval("__loadAddonFile")
    for f in toc_files():
        loader(f)
    lua.execute("__afterLoad()")
    lua.execute(f"dofile([[{test_path.as_posix()}]])")
    res = lua.eval("__results")
    return int(res.passed), int(res.failed), [str(m) for m in res.messages.values()]


def main():
    flt = sys.argv[1] if len(sys.argv) > 1 else ""
    total_p = total_f = 0
    for test in sorted(TESTS.glob("test_*.lua")):
        if flt and flt not in test.name:
            continue
        try:
            p, f, msgs = run_file(test)
        except Exception as e:  # load/runtime error outside an it()
            p, f, msgs = 0, 1, [f"{test.name}: ERROR {e}"]
        total_p += p
        total_f += f
        for m in msgs:
            print(m)
        print(f"{test.name}: {p} passed, {f} failed")
    print(f"TOTAL: {total_p} passed, {total_f} failed")
    sys.exit(1 if total_f or total_p == 0 else 0)


if __name__ == "__main__":
    main()
