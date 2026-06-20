local M = {}

--- Apply a clicks delta, clamped to zero.
---@param current integer
---@param delta integer
---@param total? integer
---@return integer
function M.apply_delta(current, delta, total)
  local base = current
  if total and base > total then
    base = total
  end

  local next_clicks = base + delta
  if next_clicks < 0 then
    return 0
  end
  if total and next_clicks > total then
    return total
  end
  return next_clicks
end

--- Resolve clicks after navigating to a page.
---@param current integer
---@param previous_page integer|nil
---@param next_page integer
---@param preserve_clicks? boolean
---@return integer
function M.resolve_for_navigation(current, previous_page, next_page, preserve_clicks)
  if preserve_clicks and previous_page == next_page then
    return current
  end
  return 0
end

local function parse_at_value(raw)
  if not raw or raw == "" then
    return nil
  end

  local single = raw:match("^%s*([+-]?%d+)%s*$")
  if single then
    return tonumber(single)
  end

  local max_value = nil
  for value in raw:gmatch("[+-]?%d+") do
    local number = tonumber(value)
    if number and (not max_value or number > max_value) then
      max_value = number
    end
  end
  return max_value
end

--- Estimate Slidev clicksTotal from v-click directives in one slide.
--- Returns nil when no supported click directive is found.
---@param lines string[]
---@return integer|nil
function M.estimate_total(lines)
  local offset = 0
  local total = 0
  local found = false
  local in_code_block = false
  local code_opening = nil

  for _, line in ipairs(lines) do
    if in_code_block then
      if line:match("^" .. code_opening:gsub("(%W)", "%%%1")) then
        in_code_block = false
        code_opening = nil
      end
    elseif line:match("^%s*```") then
      in_code_block = true
      code_opening = line:match("^(%s*`+)")
    else
      local pos = 1
      while true do
        local start_pos, end_pos = line:find("v%-[%w%-]+", pos)
        if not start_pos then
          break
        end

        local directive = line:sub(start_pos, end_pos)
        if directive == "v-click" or directive == "v-click-hide" or directive == "v-after" then
          found = true
          local tail = line:sub(end_pos + 1)
          local raw_at = tail:match("^[%w%._%-:]*%s*=%s*[\"']([^\"']+)[\"']")
          local at = parse_at_value(raw_at)

          if directive == "v-after" then
            total = math.max(total, offset)
          elseif at == nil then
            offset = offset + 1
            total = math.max(total, offset)
          elseif raw_at and raw_at:match("^%s*[+-]") then
            offset = offset + at
            total = math.max(total, offset)
          else
            total = math.max(total, at)
          end
        end

        pos = end_pos + 1
      end
    end
  end

  if not found then
    return nil
  end
  return math.max(0, total)
end

return M
