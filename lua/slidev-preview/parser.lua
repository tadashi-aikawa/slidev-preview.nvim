local M = {}

local function trim_end(line)
  return line:match("^(.-)%s*$") or ""
end

local function is_slide_separator(line)
  return line:match("^%-%-%-") and not line:match("^%-%-%-%-")
end

local function find_slide_range(lines, target_page)
  local page = 1
  local slide_start = 1
  local i = 1
  local total = #lines

  while i <= total do
    local line = trim_end(lines[i])

    if is_slide_separator(line) then
      if i > 1 then
        if page == target_page then
          return slide_start, i - 1
        end
        page = page + 1
        slide_start = i
      end

      local next_line = (i + 1 <= total) and lines[i + 1] or nil
      if next_line and next_line:match("%S") then
        i = i + 1
        while i <= total do
          local fline = trim_end(lines[i])
          if fline == "---" then
            break
          end
          i = i + 1
        end
      end
    elseif line:match("^%s*```") then
      local opening = line:match("^(%s*`+)")
      i = i + 1
      while i <= total do
        if lines[i]:match("^" .. opening:gsub("(%W)", "%%%1")) then
          break
        end
        i = i + 1
      end
    end

    i = i + 1
  end

  if page == target_page then
    return slide_start, total
  end

  return nil, nil
end

local function find_frontmatter_close(lines, start_line, end_line)
  for i = start_line, end_line do
    if trim_end(lines[i]) == "---" then
      return i
    end
  end
  return nil
end

--- Determine the slide page number at a given line (1-indexed).
--- Ports Slidev's parseSync algorithm: handles frontmatter blocks, code blocks, and --- separators.
---@param lines string[] buffer lines (1-indexed)
---@param cursor_line integer 1-indexed line number
---@return integer page 1-indexed page number
function M.get_page_at_line(lines, cursor_line)
  local page = 1
  local i = 1
  local total = #lines

  while i <= total do
    if i > cursor_line then
      break
    end

    local line = trim_end(lines[i])

    -- Check for slide separator: starts with --- but not ---- or more
    if is_slide_separator(line) then
      -- This is a slide boundary (if not the very first line of the file)
      if i > 1 then
        page = page + 1
      end

      -- Check if next line has content (= frontmatter block)
      local next_line = (i + 1 <= total) and lines[i + 1] or nil
      if next_line and next_line:match("%S") then
        -- Frontmatter detected: skip to the closing ---
        i = i + 1
        while i <= total do
          local fline = trim_end(lines[i])
          if fline == "---" then
            break
          end
          i = i + 1
        end
      end

    -- Skip code blocks (triple backtick pairs)
    elseif line:match("^%s*```") then
      local opening = line:match("^(%s*`+)")
      i = i + 1
      while i <= total do
        if lines[i]:match("^" .. opening:gsub("(%W)", "%%%1")) then
          break
        end
        i = i + 1
      end
    end

    i = i + 1
  end

  return page
end

--- Extract the lines for a given slide page.
---@param lines string[] buffer lines (1-indexed)
---@param target_page integer 1-indexed page number
---@return string[] slide lines
function M.get_slide_lines(lines, target_page)
  local page = 1
  local slide_start = 1
  local i = 1
  local total = #lines

  while i <= total do
    local line = trim_end(lines[i])

    -- Check for slide separator: starts with --- but not ---- or more
    if is_slide_separator(line) then
      -- This is a slide boundary (if not the very first line of the file)
      if i > 1 then
        if page == target_page then
          return vim.list_slice(lines, slide_start, i - 1)
        end
        page = page + 1
        slide_start = i
      end

      -- Check if next line has content (= frontmatter block)
      local next_line = (i + 1 <= total) and lines[i + 1] or nil
      if next_line and next_line:match("%S") then
        -- Frontmatter detected: skip to the closing ---
        i = i + 1
        while i <= total do
          local fline = trim_end(lines[i])
          if fline == "---" then
            break
          end
          i = i + 1
        end
      end

    -- Skip code blocks (triple backtick pairs)
    elseif line:match("^%s*```") then
      local opening = line:match("^(%s*`+)")
      i = i + 1
      while i <= total do
        if lines[i]:match("^" .. opening:gsub("(%W)", "%%%1")) then
          break
        end
        i = i + 1
      end
    end

    i = i + 1
  end

  if page == target_page then
    return vim.list_slice(lines, slide_start, total)
  end

  return {}
end

--- Find the first content line for a given slide page.
---@param lines string[] buffer lines (1-indexed)
---@param target_page integer 1-indexed page number
---@return integer|nil line 1-indexed content line, or nil when page does not exist
function M.get_slide_content_start_line(lines, target_page)
  if target_page < 1 then
    return nil
  end

  local slide_start, slide_end = find_slide_range(lines, target_page)
  if not slide_start or not slide_end then
    return nil
  end

  local content_start = slide_start
  if is_slide_separator(trim_end(lines[content_start])) then
    local close_line = find_frontmatter_close(lines, content_start + 1, slide_end)
    if close_line then
      content_start = close_line + 1
    else
      content_start = content_start + 1
    end
  end

  for line = content_start, slide_end do
    if lines[line]:match("%S") then
      return line
    end
  end

  return math.max(1, math.min(content_start, slide_end))
end

return M
