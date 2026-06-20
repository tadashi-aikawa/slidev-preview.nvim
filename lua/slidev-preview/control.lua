local M = {}

M.actions = {
  "next_slide",
  "previous_slide",
  "forward",
  "backward",
  "exit",
}

M.default_keys = {
  next_slide = { "j" },
  previous_slide = { "k" },
  forward = { "l" },
  backward = { "h" },
  exit = { "q", "<Esc>", "<C-c>" },
}

local function as_list(value)
  if type(value) == "string" then
    return { value }
  end
  if type(value) == "table" then
    return value
  end
  return {}
end

local function normalize_key(key)
  return vim.api.nvim_replace_termcodes(key, true, true, true)
end

--- Resolve control keys by action, replacing defaults only for configured actions.
---@param keys? table
---@return table<string,string[]>
function M.resolve_keys(keys)
  local resolved = {}
  keys = keys or {}

  for _, action in ipairs(M.actions) do
    local configured = keys[action]
    if configured == nil then
      configured = M.default_keys[action]
    end
    resolved[action] = as_list(configured)
  end

  return resolved
end

--- Build a normalized key-to-action map.
---@param keys? table
---@return table<string,string>
function M.build_actions(keys)
  local actions = {}
  local resolved = M.resolve_keys(keys)

  for _, action in ipairs(M.actions) do
    local action_keys = resolved[action]
    for _, key in ipairs(action_keys) do
      actions[normalize_key(key)] = action
    end
  end

  return actions
end

--- Return an action for the pressed key.
---@param actions table<string,string>
---@param key string
---@return string|nil
function M.action_for_key(actions, key)
  return actions[key]
end

---@param current integer
---@param total integer|nil
---@return string
function M.resolve_forward_action(current, total)
  if total and current < total then
    return "clicks_increment"
  end
  return "next_slide"
end

---@param current integer
---@return string
function M.resolve_backward_action(current)
  if current > 0 then
    return "clicks_decrement"
  end
  return "previous_slide"
end

---@param total integer|nil
---@return integer
function M.resolve_previous_slide_clicks(total)
  return total or 0
end

return M
