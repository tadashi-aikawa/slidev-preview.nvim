local parser = require("slidev-preview.parser")
local http = require("slidev-preview.http")
local server = require("slidev-preview.server")

local M = {}

local config = {
  port = 3030,
  debounce_ms = 200,
  slidev_bin = "npx slidev",
}

local state = {
  enabled = false,
  last_page = nil,
  debounce_timer = nil,
  augroup = nil,
  slides_path = nil,
  root_dir = nil,
}

--- Return true if the path looks like a Slidev markdown entrypoint.
---@param path string
---@return boolean
local function is_slidev_file(path)
  return path:match("[/\\]slides?%.md$") ~= nil
end

--- Get the current buffer path if it is a Slidev markdown entrypoint.
---@return string|nil
local function get_current_slidev_file()
  local bufname = vim.api.nvim_buf_get_name(0)
  if bufname == "" or not is_slidev_file(bufname) then
    return nil
  end
  return vim.fn.fnamemodify(bufname, ":p")
end

--- Return true if current buffer is the presentation started by this plugin.
---@return boolean
local function is_active_slidev_file()
  local path = get_current_slidev_file()
  return path ~= nil and path == state.slides_path
end

--- Send navigation request to Slidev dev server.
---@param page integer
local function navigate_to_page(page)
  if page == state.last_page then
    return
  end
  state.last_page = page

  local body = vim.json.encode({
    data = {
      page = page,
      clicks = 0,
      clicksTotal = 0,
      lastUpdate = {
        id = "neovim_slidev_preview",
        type = "presenter",
        time = math.floor(vim.uv.now()),
      },
    },
  })

  http.post("127.0.0.1", config.port, "/@server-reactive/nav", body)
end

--- Calculate and navigate to the current page based on cursor position.
local function sync_page()
  if not is_active_slidev_file() then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local page = parser.get_page_at_line(lines, cursor_line)
  navigate_to_page(page)
end

--- Debounced sync: reset timer on each cursor move.
local function debounced_sync()
  if state.debounce_timer then
    state.debounce_timer:stop()
    if not state.debounce_timer:is_closing() then
      state.debounce_timer:close()
    end
  end

  state.debounce_timer = vim.defer_fn(function()
    sync_page()
  end, config.debounce_ms)
end

--- Enable cursor tracking autocmds.
local function enable_tracking()
  if state.enabled then
    return
  end

  state.augroup = vim.api.nvim_create_augroup("SlidevPreview", { clear = true })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = state.augroup,
    pattern = { "slide.md", "slides.md" },
    callback = debounced_sync,
  })

  state.enabled = true
end

--- Disable cursor tracking autocmds.
local function disable_tracking()
  if not state.enabled then
    return
  end

  if state.augroup then
    vim.api.nvim_del_augroup_by_id(state.augroup)
    state.augroup = nil
  end

  if state.debounce_timer then
    state.debounce_timer:stop()
    if not state.debounce_timer:is_closing() then
      state.debounce_timer:close()
    end
    state.debounce_timer = nil
  end

  state.enabled = false
  state.last_page = nil
end

--- Start preview: launch dev server and optionally open browser.
---@param open_browser boolean
local function start_preview(open_browser)
  local slides_path = get_current_slidev_file()
  if not slides_path then
    vim.notify("[slidev-preview] Current buffer is not slide.md or slides.md", vim.log.levels.WARN)
    return
  end

  if server.is_running() then
    if state.slides_path == slides_path then
      vim.notify("[slidev-preview] Server is already running", vim.log.levels.WARN)
      enable_tracking()
      return
    end

    vim.notify("[slidev-preview] Server is already running for " .. (state.root_dir or "another directory"), vim.log.levels.WARN)
    return
  end

  state.slides_path = slides_path
  state.root_dir = vim.fn.fnamemodify(slides_path, ":h")

  local started = server.start({
    port = config.port,
    slidev_bin = config.slidev_bin,
    open_browser = open_browser,
    cwd = state.root_dir,
  })
  if not started then
    state.slides_path = nil
    state.root_dir = nil
    return
  end
  enable_tracking()
end

--- Start preview: launch dev server without opening browser.
local function cmd_start()
  start_preview(false)
end

--- Start preview: launch dev server and open browser.
local function cmd_start_and_open()
  start_preview(true)
end

--- Stop preview: stop dev server + disable cursor sync.
local function cmd_stop()
  disable_tracking()
  server.stop()
  state.slides_path = nil
  state.root_dir = nil
end

--- Open browser to current page (assumes server is running).
local function cmd_open()
  local slides_path = get_current_slidev_file()

  if state.slides_path and not is_active_slidev_file() then
    vim.notify("[slidev-preview] Current buffer is not the started Slidev file", vim.log.levels.WARN)
    return
  end

  if not state.slides_path then
    if not slides_path then
      vim.notify("[slidev-preview] Current buffer is not slide.md or slides.md", vim.log.levels.WARN)
      return
    end
    state.slides_path = slides_path
    state.root_dir = vim.fn.fnamemodify(slides_path, ":h")
  end

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local page = parser.get_page_at_line(lines, cursor_line)
  server.open_browser(config.port, page)
  enable_tracking()
end

--- Show current status.
local function cmd_status()
  local parts = {}
  table.insert(parts, "Server: " .. (server.is_running() and "running" or "stopped"))
  table.insert(parts, "Port: " .. config.port)
  table.insert(parts, "Tracking: " .. (state.enabled and "enabled" or "disabled"))
  if state.root_dir then
    table.insert(parts, "Root: " .. state.root_dir)
  end
  if state.last_page then
    table.insert(parts, "Page: " .. state.last_page)
  end
  vim.notify("[slidev-preview] " .. table.concat(parts, " | "))
end

--- Setup the plugin.
---@param opts? table
function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})

  vim.api.nvim_create_user_command("SlidevPreviewStart", cmd_start, { desc = "Start Slidev preview server" })
  vim.api.nvim_create_user_command("SlidevPreviewStartAndOpen", cmd_start_and_open, { desc = "Start Slidev preview server and open browser" })
  vim.api.nvim_create_user_command("SlidevPreviewStop", cmd_stop, { desc = "Stop Slidev preview" })
  vim.api.nvim_create_user_command("SlidevPreviewOpen", cmd_open, { desc = "Open browser to current slide" })
  vim.api.nvim_create_user_command("SlidevPreviewStatus", cmd_status, { desc = "Show Slidev preview status" })

  -- Clean up on Neovim exit to prevent zombie processes
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      if server.is_running() then
        server.stop()
      end
      disable_tracking()
    end,
  })
end

return M
