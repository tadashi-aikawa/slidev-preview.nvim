local M = {}

--- Prepend an icon (when set) to a piece of text.
---@param icon string|nil
---@param text string
---@return string
local function with_icon(icon, text)
  if icon and icon ~= "" then
    return icon .. " " .. text
  end
  return text
end

--- Build the winbar string for a synced Slidev buffer.
---
--- Pure function: receives a snapshot of the plugin state and returns the
--- winbar string (including highlight items). Returns "" when the window is
--- not showing the active Slidev buffer.
---
--- Normal mode shows only the page. Control mode additionally shows a
--- `CONTROL` label and the current clicks.
---@param snapshot table|nil { active, control_active, page, clicks, clicks_total, icons }
---@return string
function M.winbar_text(snapshot)
  if not snapshot or not snapshot.active then
    return ""
  end

  local icons = snapshot.icons or {}
  local page = snapshot.page and tostring(snapshot.page) or "-"

  if snapshot.control_active then
    local parts = {
      with_icon(icons.control, "CONTROL"),
      with_icon(icons.slide, page),
    }
    if snapshot.clicks_total and snapshot.clicks_total > 0 then
      local clicks = string.format("%d/%d", snapshot.clicks or 0, snapshot.clicks_total)
      table.insert(parts, with_icon(icons.click, clicks))
    end
    return "%#SlidevPreviewControl# " .. table.concat(parts, "  ") .. " %*"
  end

  return "%#SlidevPreviewWinbar# " .. with_icon(icons.slide, page) .. " %*"
end

return M
