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
local control = require("slidev-preview.control")

local function keycode(key)
  return vim.api.nvim_replace_termcodes(key, true, true, true)
end

local function action_for_sequence(actions, keys)
  local index = 1
  return control.action_for_input(actions, keys[1], function()
    index = index + 1
    return keys[index]
  end)
end

print("control")

test("default keys map to actions", function()
  local actions = control.build_actions()

  assert_eq(control.action_for_key(actions, "j"), "next_slide", "j = next slide")
  assert_eq(control.action_for_key(actions, "k"), "previous_slide", "k = previous slide")
  assert_eq(control.action_for_key(actions, "G"), "last_slide", "G = last slide")
  assert_eq(control.action_for_key(actions, "l"), "forward", "l = forward")
  assert_eq(control.action_for_key(actions, "h"), "backward", "h = backward")
  assert_eq(control.action_for_key(actions, "q"), "exit", "q = exit")
  assert_eq(control.action_for_key(actions, keycode("<Esc>")), "exit", "<Esc> = exit")
end)

test("configured action keys replace that action only", function()
  local actions = control.build_actions({
    next_slide = { "n", "<Right>" },
    exit = "x",
  })

  assert_eq(control.action_for_key(actions, "n"), "next_slide", "custom next slide key works")
  assert_eq(control.action_for_key(actions, keycode("<Right>")), "next_slide", "custom special next slide key works")
  assert_eq(control.action_for_key(actions, "j"), nil, "default next slide key is replaced")
  assert_eq(control.action_for_key(actions, "k"), "previous_slide", "unspecified previous slide key keeps default")
  assert_eq(control.action_for_key(actions, "x"), "exit", "custom exit key works")
  assert_eq(control.action_for_key(actions, "q"), nil, "default exit key is replaced")
end)

test("multi-key first slide sequence resolves to action", function()
  local actions = control.build_actions()
  local action = action_for_sequence(actions, { "g", "g" })

  assert_eq(action, "first_slide", "gg = first slide")
end)

test("count before last slide key resolves to target page", function()
  local actions = control.build_actions()
  local action, opts = action_for_sequence(actions, { "5", "G" })

  assert_eq(action, "goto_slide", "5G = goto slide")
  assert_eq(opts.page, 5, "5G targets page 5")

  action, opts = action_for_sequence(actions, { "1", "5", "G" })

  assert_eq(action, "goto_slide", "15G = goto slide")
  assert_eq(opts.page, 15, "15G targets page 15")
end)

test("count before next and previous slide keys resolves to relative movement", function()
  local actions = control.build_actions()
  local action, opts = action_for_sequence(actions, { "5", "j" })

  assert_eq(action, "move_slide", "5j = move slide")
  assert_eq(opts.delta, 5, "5j moves forward 5 slides")

  action, opts = action_for_sequence(actions, { "1", "5", "j" })

  assert_eq(action, "move_slide", "15j = move slide")
  assert_eq(opts.delta, 15, "15j moves forward 15 slides")

  action, opts = action_for_sequence(actions, { "5", "k" })

  assert_eq(action, "move_slide", "5k = move slide")
  assert_eq(opts.delta, -5, "5k moves backward 5 slides")
end)

test("count before custom next and previous slide keys resolves to relative movement", function()
  local actions = control.build_actions({
    next_slide = { "n" },
    previous_slide = { "p" },
  })
  local action, opts = action_for_sequence(actions, { "5", "n" })

  assert_eq(action, "move_slide", "5n = move slide")
  assert_eq(opts.delta, 5, "5n moves forward 5 slides")

  action, opts = action_for_sequence(actions, { "5", "p" })

  assert_eq(action, "move_slide", "5p = move slide")
  assert_eq(opts.delta, -5, "5p moves backward 5 slides")
end)

test("count before unsupported action does not resolve", function()
  local actions = control.build_actions()
  local action = action_for_sequence(actions, { "5", "l" })

  assert_eq(action, nil, "5l is unsupported")

  action = action_for_sequence(actions, { "5", "h" })

  assert_eq(action, nil, "5h is unsupported")

  action = action_for_sequence(actions, { "5", "q" })

  assert_eq(action, nil, "5q is unsupported")

  action = action_for_sequence(actions, { "5", "g", "g" })

  assert_eq(action, nil, "5gg is unsupported")
end)

test("forward uses clicks while there are remaining clicks", function()
  assert_eq(control.resolve_forward_action(0, 2), "clicks_increment", "0 of 2 clicks increments")
  assert_eq(control.resolve_forward_action(1, 2), "clicks_increment", "1 of 2 clicks increments")
  assert_eq(control.resolve_forward_action(2, 2), "next_slide", "2 of 2 clicks moves to next slide")
  assert_eq(control.resolve_forward_action(0, nil), "next_slide", "no clicksTotal moves to next slide")
end)

test("backward uses clicks only when current clicks is positive", function()
  assert_eq(control.resolve_backward_action(2), "clicks_decrement", "2 clicks decrements")
  assert_eq(control.resolve_backward_action(1), "clicks_decrement", "1 click decrements")
  assert_eq(control.resolve_backward_action(0), "previous_slide", "0 clicks moves to previous slide")
end)

test("previous slide starts from max clicks when available", function()
  assert_eq(control.resolve_previous_slide_clicks(3), 3, "previous slide with clicks starts from max")
  assert_eq(control.resolve_previous_slide_clicks(nil), 0, "previous slide without clicks starts from 0")
end)

print("")
print(string.format("Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  os.exit(1)
end
