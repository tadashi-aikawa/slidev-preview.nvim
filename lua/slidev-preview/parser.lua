local M = {}

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

    local line = lines[i]:match("^(.-)%s*$") or "" -- trimEnd

    -- Check for slide separator: starts with --- but not ---- or more
    if line:match("^%-%-%-") and not line:match("^%-%-%-%-") then
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
          local fline = lines[i]:match("^(.-)%s*$") or ""
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
    local line = lines[i]:match("^(.-)%s*$") or "" -- trimEnd

    -- Check for slide separator: starts with --- but not ---- or more
    if line:match("^%-%-%-") and not line:match("^%-%-%-%-") then
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
          local fline = lines[i]:match("^(.-)%s*$") or ""
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

return M
