local M = {}

M.actions = {
  "next_slide",
  "previous_slide",
  "first_slide",
  "last_slide",
  "forward",
  "backward",
  "exit",
}

M.default_keys = {
  next_slide = { "j" },
  previous_slide = { "k" },
  first_slide = { "gg" },
  last_slide = { "G" },
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

local function is_digit(key)
  return key:match("^%d$") ~= nil
end

local function has_longer_key_with_prefix(actions, prefix)
  for key, _ in pairs(actions) do
    if key ~= prefix and key:sub(1, #prefix) == prefix then
      return true
    end
  end
  return false
end

--- Resolve an action from the first pressed key, reading more keys for sequences/counts.
---@param actions table<string,string>
---@param first_key string
---@param read_key fun(): string|nil
---@return string|nil action
---@return table|nil opts
function M.action_for_input(actions, first_key, read_key)
  if is_digit(first_key) then
    local digits = first_key

    while true do
      local next_key = read_key()
      if not next_key or next_key == "" then
        return nil
      end

      if is_digit(next_key) then
        digits = digits .. next_key
      elseif actions[next_key] == "next_slide" then
        return "move_slide", { delta = tonumber(digits) }
      elseif actions[next_key] == "previous_slide" then
        return "move_slide", { delta = -tonumber(digits) }
      elseif actions[next_key] == "last_slide" then
        return "goto_slide", { page = tonumber(digits) }
      else
        return nil
      end
    end
  end

  local action = M.action_for_key(actions, first_key)
  if action then
    return action
  end

  if not has_longer_key_with_prefix(actions, first_key) then
    return nil
  end

  local key = first_key
  while has_longer_key_with_prefix(actions, key) do
    local next_key = read_key()
    if not next_key or next_key == "" then
      return nil
    end

    key = key .. next_key
    action = M.action_for_key(actions, key)
    if action then
      return action
    end
  end

  return nil
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
