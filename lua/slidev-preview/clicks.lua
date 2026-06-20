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

local function parse_number_attr(line, name, default)
  local raw = line:match(name .. "%s*=%s*[\"'](%d+)[\"']")
  local value = raw and tonumber(raw) or nil
  if value and value > 0 then
    return value
  end
  return default
end

local function get_markdown_list_depth(line)
  local indent, marker = line:match("^(%s*)([-*+]%s+)")
  if not marker then
    indent, marker = line:match("^(%s*)(%d+[.)]%s+)")
  end
  if not marker then
    return nil
  end

  local spaces = indent:gsub("\t", "  "):len()
  return math.floor(spaces / 2) + 1
end

local function clicks_for_v_clicks_block(item_count, every)
  if item_count <= 0 then
    return 0
  end
  return math.ceil(item_count / every)
end

local function is_code_highlight_stage(stage)
  local value = stage:match("^%s*(.-)%s*$")
  if value == "" then
    return false
  end
  if value == "all" or value == "none" or value == "*" then
    return true
  end
  return value:match("^[%d,%-%s]+$") ~= nil and value:match("%d") ~= nil
end

local function count_code_highlight_stages(raw)
  if not raw:find("|", 1, true) then
    return nil
  end

  local stages = 0
  for stage in (raw .. "|"):gmatch("([^|]*)|") do
    if not is_code_highlight_stage(stage) then
      return nil
    end
    stages = stages + 1
  end

  if stages <= 1 then
    return nil
  end
  return stages
end

local function parse_code_animation(line)
  local stages = nil
  local raw_at = nil

  for raw in line:gmatch("{([^{}]*)}") do
    stages = stages or count_code_highlight_stages(raw)
    raw_at = raw_at or raw:match("[\"']?at[\"']?%s*:%s*[\"']?([+-]?%d+)[\"']?")
  end

  if not stages then
    return nil, nil
  end
  return stages - 1, raw_at
end

local function apply_code_animation(line, offset, total)
  local code_clicks, raw_at = parse_code_animation(line)
  if not code_clicks or code_clicks <= 0 then
    return offset, total, false
  end

  local at = parse_at_value(raw_at)
  if at == nil then
    offset = offset + code_clicks
    total = math.max(total, offset)
  elseif raw_at and raw_at:match("^%s*[+-]") then
    offset = offset + at + code_clicks
    total = math.max(total, offset)
  else
    total = math.max(total, at + code_clicks)
  end

  return offset, total, true
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
  local v_clicks_block = nil

  for _, line in ipairs(lines) do
    if in_code_block then
      if line:match("^" .. code_opening:gsub("(%W)", "%%%1")) then
        in_code_block = false
        code_opening = nil
      end
    elseif v_clicks_block then
      if line:match("</v%-clicks>") then
        local clicks_count = clicks_for_v_clicks_block(v_clicks_block.item_count, v_clicks_block.every)
        if clicks_count > 0 then
          found = true
          offset = offset + clicks_count
          total = math.max(total, offset)
        end
        v_clicks_block = nil
      else
        local depth = get_markdown_list_depth(line)
        if depth and depth <= v_clicks_block.depth then
          v_clicks_block.item_count = v_clicks_block.item_count + 1
        end
      end
    elseif line:match("^%s*```") then
      local has_code_animation
      offset, total, has_code_animation = apply_code_animation(line, offset, total)
      found = found or has_code_animation

      in_code_block = true
      code_opening = line:match("^(%s*`+)")
    elseif line:match("^%s*<<<%s+") then
      local has_code_animation
      offset, total, has_code_animation = apply_code_animation(line, offset, total)
      found = found or has_code_animation
    elseif line:match("<v%-clicks[%s>]") then
      v_clicks_block = {
        depth = parse_number_attr(line, "depth", 1),
        every = parse_number_attr(line, "every", 1),
        item_count = 0,
      }
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

  if v_clicks_block then
    local clicks_count = clicks_for_v_clicks_block(v_clicks_block.item_count, v_clicks_block.every)
    if clicks_count > 0 then
      found = true
      offset = offset + clicks_count
      total = math.max(total, offset)
    end
  end

  if not found then
    return nil
  end
  return math.max(0, total)
end

return M
