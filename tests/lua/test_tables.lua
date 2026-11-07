local T = __ns.Tables

describe("Tables.merge", function()
  it("fills missing keys recursively", function()
    local saved = { b = {} }
    T.merge({ a = 1, b = { c = 2 } }, saved)
    assertEq(saved, { a = 1, b = { c = 2 } })
  end)
  it("never overwrites existing values", function()
    local saved = { a = 5, b = { c = false } }
    T.merge({ a = 1, b = { c = true, d = 3 } }, saved)
    assertEq(saved, { a = 5, b = { c = false, d = 3 } })
  end)
  it("keeps keys absent from defaults", function()
    local saved = { extra = "x" }
    T.merge({ a = 1 }, saved)
    assertEq(saved.extra, "x")
  end)
  it("copies default tables instead of aliasing them", function()
    local defaults = { list = { 1, 2 } }
    local saved = {}
    T.merge(defaults, saved)
    saved.list[1] = 99
    assertEq(defaults.list[1], 1)
  end)
end)

describe("Tables.copy", function()
  it("deep copies without aliasing", function()
    local src = { a = { b = { c = 1 } } }
    local c = T.copy(src)
    assertEq(c, src)
    c.a.b.c = 2
    assertEq(src.a.b.c, 1)
  end)
end)

describe("Tables paths", function()
  it("gets and sets dotted paths, creating parents", function()
    local root = { a = { b = 1 } }
    assertEq((T.getPath(root, "a.b")), 1)
    assertNil((T.getPath(root, "a.x.y")))
    T.setPath(root, "a.c.d", true)
    assertEq(root.a.c.d, true)
    T.setPath(root, "list.2", "v")
    assertEq(root.list[2], "v")
  end)
end)
