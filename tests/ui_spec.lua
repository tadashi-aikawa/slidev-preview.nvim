--- Test helper: simple assertion with descriptive messages
local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error(string.format("FAIL: %s\n  expected: %s\n  actual:   %s", msg, tostring(expected), tostring(actual)), 2)
  end
end

local function assert_contains(haystack, needle, msg)
  if type(haystack) ~= "string" or not haystack:find(needle, 1, true) then
    error(string.format("FAIL: %s\n  expected to contain: %s\n  actual:   %s", msg, tostring(needle), tostring(haystack)), 2)
  end
end

local function assert_not_contains(haystack, needle, msg)
  if type(haystack) == "string" and haystack:find(needle, 1, true) then
    error(string.format("FAIL: %s\n  expected NOT to contain: %s\n  actual:   %s", msg, tostring(needle), tostring(haystack)), 2)
  end
end

local passed = 0
local failed = 0

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print("  ✓ " .. name)
  else
    failed = failed + 1
    print("  ✗ " .. name)
    print("    " .. err)
  end
end

package.path = "lua/?.lua;lua/?/init.lua;" .. package.path
local ui = require("slidev-preview.ui")

test("returns empty string when not active", function()
  assert_eq(ui.winbar_text(nil), "", "nil snapshot is empty")
  assert_eq(ui.winbar_text({ active = false }), "", "inactive snapshot is empty")
end)

test("normal mode shows only the page (icon + number)", function()
  local text = ui.winbar_text({
    active = true,
    control_active = false,
    page = 28,
    clicks = 1,
    clicks_total = 2,
    icons = { slide = "S" },
  })
  assert_contains(text, "SlidevPreviewWinbar", "uses the normal highlight group")
  assert_contains(text, "S 28", "shows the slide icon and page")
  assert_not_contains(text, "click", "no click label in normal mode")
  assert_not_contains(text, "/", "no clicks counter in normal mode")
  assert_not_contains(text, "CONTROL", "no control label in normal mode")
end)

test("normal mode works without an icon", function()
  local text = ui.winbar_text({
    active = true,
    control_active = false,
    page = 5,
  })
  assert_contains(text, " 5 ", "shows just the page when no icon is set")
end)

test("normal mode shows page/total when pages_total is provided", function()
  local text = ui.winbar_text({
    active = true,
    control_active = false,
    page = 3,
    pages_total = 10,
    icons = { slide = "S" },
  })
  assert_contains(text, "S 3/10", "shows page fraction with icon")
  assert_not_contains(text, "CONTROL", "no control label in normal mode")
end)

test("control mode shows control icon, page, and clicks", function()
  local text = ui.winbar_text({
    active = true,
    control_active = true,
    page = 28,
    clicks = 1,
    clicks_total = 2,
    icons = { slide = "S", click = "C", control = "G" },
  })
  assert_contains(text, "SlidevPreviewControl", "uses the control highlight group")
  assert_contains(text, "G", "shows the control icon")
  assert_not_contains(text, "CONTROL", "no CONTROL label text")
  assert_contains(text, "S 28", "shows the page")
  assert_contains(text, "C 1/2", "shows the clicks with icon")
end)

test("control mode omits clicks when no clicks_total", function()
  local text = ui.winbar_text({
    active = true,
    control_active = true,
    page = 3,
    clicks = 0,
    clicks_total = 0,
  })
  assert_contains(text, "3", "still shows page")
  assert_not_contains(text, "/", "no clicks counter when total is 0")
end)

test("missing page renders a placeholder", function()
  local text = ui.winbar_text({
    active = true,
    control_active = false,
    page = nil,
  })
  assert_contains(text, "-", "shows placeholder when page is unknown")
end)

print("")
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  os.exit(1)
end
