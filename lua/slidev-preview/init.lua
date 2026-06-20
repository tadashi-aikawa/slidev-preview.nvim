local parser = require("slidev-preview.parser")
local http = require("slidev-preview.http")
local server = require("slidev-preview.server")
local clicks = require("slidev-preview.clicks")

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
  clicks = 0,
  clicks_total = nil,
}

local function make_last_update()
  return {
    id = "neovim_slidev_preview",
    type = "presenter",
    time = math.floor(vim.uv.now()),
  }
end

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

--- Calculate the current page based on cursor position.
---@return integer
local function get_current_page()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  return parser.get_page_at_line(lines, cursor_line)
end

--- Estimate clicksTotal for a page from the active Slidev file.
---@param page integer
---@return integer|nil
local function estimate_clicks_total(page)
  if not is_active_slidev_file() then
    return nil
  end

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local slide_lines = parser.get_slide_lines(lines, page)
  return clicks.estimate_total(slide_lines)
end

--- Send navigation request to Slidev dev server.
---@param page integer
---@param force? boolean
---@param preserve_clicks? boolean
local function navigate_to_page(page, force, preserve_clicks)
  if not force and page == state.last_page then
    return
  end

  local is_same_page = page == state.last_page
  state.clicks_total = estimate_clicks_total(page)
  state.clicks = clicks.resolve_for_navigation(state.clicks, state.last_page, page, preserve_clicks)
  state.last_page = page

  local payload
  if preserve_clicks and is_same_page then
    payload = {
      patch = {
        page = page,
        lastUpdate = make_last_update(),
      },
    }
  else
    payload = {
      data = {
        page = page,
        clicks = state.clicks,
        clicksTotal = 0,
        lastUpdate = make_last_update(),
      },
    }
  end

  local body = vim.json.encode(payload)

  http.post("127.0.0.1", config.port, "/@server-reactive/nav", body)
end

--- Send clicks patch to Slidev dev server.
---@param page integer
local function send_clicks_patch(page)
  local body = vim.json.encode({
    patch = {
      page = page,
      clicks = state.clicks,
      lastUpdate = make_last_update(),
    },
  })

  http.post("127.0.0.1", config.port, "/@server-reactive/nav", body)
end

--- Resolve the page whose clicks should be updated.
---@return integer|nil
local function resolve_clicks_page()
  if state.last_page then
    return state.last_page
  end

  if not state.slides_path then
    vim.notify(
      "[slidev-preview] Preview page is not available. Run :SlidevPreviewOpen or :SlidevPreviewStart first",
      vim.log.levels.WARN
    )
    return nil
  end

  if not is_active_slidev_file() then
    vim.notify("[slidev-preview] Current buffer is not the started Slidev file", vim.log.levels.WARN)
    return nil
  end

  local page = get_current_page()
  state.last_page = page
  state.clicks_total = estimate_clicks_total(page)
  return page
end

--- Update clicks for the previewed page.
---@param delta integer
local function update_clicks(delta)
  local page = resolve_clicks_page()
  if not page then
    return
  end

  state.clicks_total = estimate_clicks_total(page) or state.clicks_total
  state.clicks = clicks.apply_delta(state.clicks, delta, state.clicks_total)
  send_clicks_patch(page)
end

--- Move the cursor to another slide and navigate the preview.
---@param delta integer
local function move_slide(delta)
  if not state.slides_path then
    vim.notify(
      "[slidev-preview] Preview page is not available. Run :SlidevPreviewOpen or :SlidevPreviewStart first",
      vim.log.levels.WARN
    )
    return
  end

  if not is_active_slidev_file() then
    vim.notify("[slidev-preview] Current buffer is not the started Slidev file", vim.log.levels.WARN)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local current_page = parser.get_page_at_line(lines, cursor_line)
  local target_page = current_page + delta
  local target_line = parser.get_slide_content_start_line(lines, target_page)
  if not target_line then
    return
  end

  vim.api.nvim_win_set_cursor(0, { target_line, 0 })
  vim.cmd("normal! zt")
  navigate_to_page(target_page, true, false)
end

--- Calculate and navigate to the current page based on cursor position.
---@param force? boolean
---@param preserve_clicks? boolean
local function sync_page(force, preserve_clicks)
  if not is_active_slidev_file() then
    return
  end

  local page = get_current_page()
  navigate_to_page(page, force, preserve_clicks)
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

--- Sync after Slidev reloads the saved file.
local function sync_after_write()
  vim.defer_fn(function()
    sync_page(true, true)
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
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = state.augroup,
    pattern = { "slide.md", "slides.md" },
    callback = sync_after_write,
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
  state.clicks = 0
  state.clicks_total = nil
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
  state.last_page = nil
  state.clicks = 0
  state.clicks_total = nil

  local started = server.start({
    port = config.port,
    slidev_bin = config.slidev_bin,
    open_browser = open_browser,
    cwd = state.root_dir,
  })
  if not started then
    state.slides_path = nil
    state.root_dir = nil
    state.clicks = 0
    state.clicks_total = nil
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
  state.last_page = nil
  state.clicks = 0
  state.clicks_total = nil
end

--- Restart preview: stop dev server if running, then start again without opening browser.
local function cmd_restart()
  local slides_path = get_current_slidev_file()
  if not slides_path then
    vim.notify("[slidev-preview] Current buffer is not slide.md or slides.md", vim.log.levels.WARN)
    return
  end

  if server.is_running() then
    disable_tracking()
    server.stop()
    state.slides_path = nil
    state.root_dir = nil
    state.last_page = nil
    state.clicks = 0
    state.clicks_total = nil
  end

  start_preview(false)
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

  local page = get_current_page()
  server.open_browser(config.port, page)
  state.last_page = page
  state.clicks = 0
  state.clicks_total = estimate_clicks_total(page)
  enable_tracking()
end

--- Increment clicks for the previewed page.
local function cmd_clicks_increment()
  update_clicks(1)
end

--- Decrement clicks for the previewed page.
local function cmd_clicks_decrement()
  update_clicks(-1)
end

--- Move to the next slide.
local function cmd_next()
  move_slide(1)
end

--- Move to the previous slide.
local function cmd_previous()
  move_slide(-1)
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
  table.insert(parts, "Clicks: " .. state.clicks)
  if state.clicks_total then
    table.insert(parts, "ClicksTotal: " .. state.clicks_total)
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
  vim.api.nvim_create_user_command("SlidevPreviewRestart", cmd_restart, { desc = "Restart Slidev preview server" })
  vim.api.nvim_create_user_command("SlidevPreviewOpen", cmd_open, { desc = "Open browser to current slide" })
  vim.api.nvim_create_user_command(
    "SlidevPreviewClicksIncrement",
    cmd_clicks_increment,
    { desc = "Increment clicks for current Slidev preview page" }
  )
  vim.api.nvim_create_user_command(
    "SlidevPreviewClicksDecrement",
    cmd_clicks_decrement,
    { desc = "Decrement clicks for current Slidev preview page" }
  )
  vim.api.nvim_create_user_command("SlidevPreviewNext", cmd_next, { desc = "Move to next Slidev preview page" })
  vim.api.nvim_create_user_command("SlidevPreviewPrevious", cmd_previous, { desc = "Move to previous Slidev preview page" })
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
