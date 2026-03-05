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

-- Load parser
package.path = "lua/?.lua;lua/?/init.lua;" .. package.path
local parser = require("slidev-preview.parser")

print("parser.get_page_at_line")

test("file with global frontmatter", function()
  local lines = {
    "---",           -- 1
    "theme: seriph", -- 2
    "---",           -- 3
    "",              -- 4
    "# Slide 1",    -- 5
    "",              -- 6
    "---",           -- 7
    "",              -- 8
    "# Slide 2",    -- 9
    "",              -- 10
    "---",           -- 11
    "",              -- 12
    "# Slide 3",    -- 13
  }
  assert_eq(parser.get_page_at_line(lines, 1), 1, "frontmatter start = page 1")
  assert_eq(parser.get_page_at_line(lines, 2), 1, "inside frontmatter = page 1")
  assert_eq(parser.get_page_at_line(lines, 3), 1, "frontmatter end = page 1")
  assert_eq(parser.get_page_at_line(lines, 5), 1, "slide 1 content = page 1")
  assert_eq(parser.get_page_at_line(lines, 7), 2, "separator = page 2")
  assert_eq(parser.get_page_at_line(lines, 9), 2, "slide 2 content = page 2")
  assert_eq(parser.get_page_at_line(lines, 11), 3, "separator = page 3")
  assert_eq(parser.get_page_at_line(lines, 13), 3, "slide 3 content = page 3")
end)

test("per-slide frontmatter", function()
  local lines = {
    "---",             -- 1: global frontmatter (page 1)
    "theme: seriph",   -- 2
    "---",             -- 3
    "",                -- 4
    "# Slide 1",      -- 5
    "",                -- 6
    "---",             -- 7: page 2 with per-slide frontmatter
    "layout: center",  -- 8
    "---",             -- 9: frontmatter close (still page 2)
    "",                -- 10
    "# Slide 2",      -- 11
    "",                -- 12
    "---",             -- 13: page 3
    "",                -- 14
    "# Slide 3",      -- 15
  }
  assert_eq(parser.get_page_at_line(lines, 7), 2, "per-slide fm start = page 2")
  assert_eq(parser.get_page_at_line(lines, 8), 2, "inside per-slide fm = page 2")
  assert_eq(parser.get_page_at_line(lines, 9), 2, "per-slide fm end = page 2")
  assert_eq(parser.get_page_at_line(lines, 11), 2, "slide 2 content = page 2")
  assert_eq(parser.get_page_at_line(lines, 13), 3, "separator = page 3")
  assert_eq(parser.get_page_at_line(lines, 15), 3, "slide 3 content = page 3")
end)

test("code block containing ---", function()
  local lines = {
    "# Slide 1",    -- 1
    "",              -- 2
    "```markdown",   -- 3
    "---",           -- 4: inside code block, NOT a separator
    "some: yaml",   -- 5
    "---",           -- 6: still inside code block
    "```",           -- 7
    "",              -- 8
    "---",           -- 9: page 2
    "",              -- 10
    "# Slide 2",    -- 11
  }
  assert_eq(parser.get_page_at_line(lines, 1), 1, "slide 1 content = page 1")
  assert_eq(parser.get_page_at_line(lines, 4), 1, "--- inside code block = page 1")
  assert_eq(parser.get_page_at_line(lines, 6), 1, "--- inside code block = page 1")
  assert_eq(parser.get_page_at_line(lines, 7), 1, "code block close = page 1")
  assert_eq(parser.get_page_at_line(lines, 9), 2, "separator after code block = page 2")
  assert_eq(parser.get_page_at_line(lines, 11), 2, "slide 2 content = page 2")
end)

test("no frontmatter at all", function()
  local lines = {
    "# Slide 1",  -- 1
    "",            -- 2
    "---",         -- 3
    "",            -- 4
    "# Slide 2",  -- 5
    "",            -- 6
    "---",         -- 7
    "",            -- 8
    "# Slide 3",  -- 9
  }
  assert_eq(parser.get_page_at_line(lines, 1), 1, "slide 1 = page 1")
  assert_eq(parser.get_page_at_line(lines, 3), 2, "separator = page 2")
  assert_eq(parser.get_page_at_line(lines, 5), 2, "slide 2 = page 2")
  assert_eq(parser.get_page_at_line(lines, 7), 3, "separator = page 3")
  assert_eq(parser.get_page_at_line(lines, 9), 3, "slide 3 = page 3")
end)

test("single slide (no separators)", function()
  local lines = {
    "# Only Slide",
    "",
    "Some content",
  }
  assert_eq(parser.get_page_at_line(lines, 1), 1, "line 1 = page 1")
  assert_eq(parser.get_page_at_line(lines, 3), 1, "line 3 = page 1")
end)

test("empty file", function()
  local lines = { "" }
  assert_eq(parser.get_page_at_line(lines, 1), 1, "empty file = page 1")
end)

test("---- (4 dashes) is not a separator", function()
  local lines = {
    "# Slide 1",  -- 1
    "",            -- 2
    "----",        -- 3: NOT a separator (4 dashes)
    "",            -- 4
    "---",         -- 5: separator
    "",            -- 6
    "# Slide 2",  -- 7
  }
  assert_eq(parser.get_page_at_line(lines, 3), 1, "---- is not a separator = page 1")
  assert_eq(parser.get_page_at_line(lines, 5), 2, "--- is a separator = page 2")
  assert_eq(parser.get_page_at_line(lines, 7), 2, "slide 2 = page 2")
end)

test("cursor at very end of file", function()
  local lines = {
    "---",           -- 1
    "theme: default", -- 2
    "---",           -- 3
    "",              -- 4
    "# Slide 1",    -- 5
    "",              -- 6
    "---",           -- 7
    "",              -- 8
    "# Slide 2",    -- 9
    "last line",    -- 10
  }
  assert_eq(parser.get_page_at_line(lines, 10), 2, "last line = page 2")
end)

test("multiple per-slide frontmatters", function()
  local lines = {
    "---",               -- 1: global fm
    "theme: seriph",     -- 2
    "---",               -- 3
    "",                  -- 4
    "# Slide 1",        -- 5
    "",                  -- 6
    "---",               -- 7: page 2 fm
    "layout: center",    -- 8
    "---",               -- 9
    "",                  -- 10
    "# Slide 2",        -- 11
    "",                  -- 12
    "---",               -- 13: page 3 fm
    "layout: two-cols",  -- 14
    "---",               -- 15
    "",                  -- 16
    "# Slide 3",        -- 17
  }
  assert_eq(parser.get_page_at_line(lines, 5), 1, "slide 1 = page 1")
  assert_eq(parser.get_page_at_line(lines, 11), 2, "slide 2 = page 2")
  assert_eq(parser.get_page_at_line(lines, 17), 3, "slide 3 = page 3")
end)

test("frontmatter with empty lines inside", function()
  local lines = {
    "---",               -- 1
    "theme: seriph",     -- 2
    "background: url",   -- 3
    "---",               -- 4
    "",                  -- 5
    "# Slide 1",        -- 6
  }
  assert_eq(parser.get_page_at_line(lines, 2), 1, "inside fm = page 1")
  assert_eq(parser.get_page_at_line(lines, 6), 1, "slide 1 = page 1")
end)

-- Summary
print("")
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  os.exit(1)
end
