--- Test helper: simple assertion with descriptive messages
local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error(string.format("FAIL: %s\n  expected: %s\n  actual:   %s", msg, tostring(expected), tostring(actual)), 2)
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
local clicks = require("slidev-preview.clicks")

print("clicks")

test("increment clicks", function()
  assert_eq(clicks.apply_delta(0, 1), 1, "0 + 1 = 1")
  assert_eq(clicks.apply_delta(1, 1), 2, "1 + 1 = 2")
end)

test("increment clicks clamps to total", function()
  assert_eq(clicks.apply_delta(1, 1, 2), 2, "1 + 1 = 2")
  assert_eq(clicks.apply_delta(2, 1, 2), 2, "2 + 1 stays 2")
end)

test("decrement from overshot clicks uses total as the base", function()
  assert_eq(clicks.apply_delta(3, -1, 2), 1, "overshot 3 is treated as total 2 before decrement")
end)

test("decrement clicks", function()
  assert_eq(clicks.apply_delta(2, -1), 1, "2 - 1 = 1")
  assert_eq(clicks.apply_delta(1, -1), 0, "1 - 1 = 0")
end)

test("decrement clamps at zero", function()
  assert_eq(clicks.apply_delta(0, -1), 0, "0 - 1 stays 0")
  assert_eq(clicks.apply_delta(1, -3), 0, "negative result clamps to 0")
end)

test("page change resets clicks", function()
  assert_eq(clicks.resolve_for_navigation(2, 1, 2, false), 0, "moving to another page resets clicks")
end)

test("same page navigation without preserve resets clicks", function()
  assert_eq(clicks.resolve_for_navigation(2, 1, 1, false), 0, "forced same page navigation resets clicks")
end)

test("same page navigation with preserve keeps clicks", function()
  assert_eq(clicks.resolve_for_navigation(2, 1, 1, true), 2, "same page preserve keeps clicks")
end)

test("different page navigation with preserve resets clicks", function()
  assert_eq(clicks.resolve_for_navigation(2, 1, 2, true), 0, "different page preserve resets clicks")
end)

test("estimate total treats v-after as the same click", function()
  local lines = {
    "# Animation",
    "",
    "<div v-click.fade-in>",
    "first",
    "</div>",
    "",
    "<div v-click.fade-in>",
    "second",
    "</div>",
    "",
    "<div v-after.fade-in>",
    "with second",
    "</div>",
  }

  assert_eq(clicks.estimate_total(lines), 2, "two v-clicks and one v-after = clicksTotal 2")
end)

test("estimate total ignores code blocks", function()
  local lines = {
    "```html",
    "<div v-click>",
    "```",
    "<div v-click>",
  }

  assert_eq(clicks.estimate_total(lines), 1, "v-click inside code block is ignored")
end)

print("")
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  os.exit(1)
end
