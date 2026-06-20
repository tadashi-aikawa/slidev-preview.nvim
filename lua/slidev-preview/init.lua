local parser = require("slidev-preview.parser")
local http = require("slidev-preview.http")
local server = require("slidev-preview.server")
local clicks = require("slidev-preview.clicks")
local control = require("slidev-preview.control")
local ui = require("slidev-preview.ui")

local M = {}

local config = {
  port = 3030,
  debounce_ms = 200,
  slidev_bin = "npx slidev",
  slide_position = "zz",
  control = {
    keys = nil,
  },
  ui = {
    winbar = true,
    icons = {
      slide = "page",
      click = "click",
      control = "",
    },
  },
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
  control_active = false,
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

local WINBAR_EXPR = "%{%v:lua.require'slidev-preview'.winbar()%}"

--- Resolve the Slidev entrypoint path shown in a buffer, if any.
---@param buf integer
---@return string|nil
local function buf_slidev_path(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" or not is_slidev_file(name) then
    return nil
  end
  return vim.fn.fnamemodify(name, ":p")
end

--- Build the winbar snapshot for the buffer shown in `win` (0 = current window).
---@param win integer
---@return table
local function build_winbar_snapshot(win)
  local buf
  if win ~= 0 and vim.api.nvim_win_is_valid(win) then
    buf = vim.api.nvim_win_get_buf(win)
  else
    buf = vim.api.nvim_get_current_buf()
  end

  local active = state.slides_path ~= nil and buf_slidev_path(buf) == state.slides_path
  return {
    active = active,
    control_active = state.control_active,
    page = state.last_page,
    clicks = state.clicks,
    clicks_total = state.clicks_total,
    icons = (config.ui and config.ui.icons) or {},
  }
end

--- Winbar string for the synced buffer.
---
--- Usable both as the plugin's own winbar expression and as a lualine
--- component. Honors `vim.g.actual_curwin` (set by lualine) so the right
--- window's buffer is checked when rendering inactive winbars.
---@return string
function M.winbar()
  local win = 0
  local cur = vim.g.actual_curwin
  if cur then
    local w = tonumber(cur)
    if w and vim.api.nvim_win_is_valid(w) then
      win = w
    end
  end
  return ui.winbar_text(build_winbar_snapshot(win))
end

--- Apply or clear the plugin winbar on a single window based on its buffer.
---@param win? integer
local function apply_winbar(win)
  if not (config.ui and config.ui.winbar) then
    return
  end

  win = win or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(win) then
    return
  end

  local buf = vim.api.nvim_win_get_buf(win)
  local name = vim.api.nvim_buf_get_name(buf)
  local is_sync = name ~= ""
    and is_slidev_file(name)
    and state.slides_path ~= nil
    and vim.fn.fnamemodify(name, ":p") == state.slides_path

  local current = vim.api.nvim_get_option_value("winbar", { scope = "local", win = win })
  if is_sync then
    if current ~= WINBAR_EXPR then
      vim.api.nvim_set_option_value("winbar", WINBAR_EXPR, { scope = "local", win = win })
    end
  elseif current == WINBAR_EXPR then
    vim.api.nvim_set_option_value("winbar", "", { scope = "local", win = win })
  end
end

--- Remove the plugin winbar from every window it set it on.
local function clear_all_winbar()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local ok, current = pcall(vim.api.nvim_get_option_value, "winbar", { scope = "local", win = win })
    if ok and current == WINBAR_EXPR then
      vim.api.nvim_set_option_value("winbar", "", { scope = "local", win = win })
    end
  end
end

local function refresh_statusline()
  pcall(vim.cmd, "redrawstatus!")

  local ok, lualine = pcall(require, "lualine")
  if ok and type(lualine.refresh) == "function" then
    pcall(lualine.refresh, {
      force = true,
      scope = "tabpage",
      place = { "statusline", "winbar" },
    })
  end
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

--- Resolve the normal-mode command used after moving to another slide.
---@return string
local function resolve_slide_position()
  local slide_position = config.slide_position
  if slide_position == "zt" or slide_position == "zz" or slide_position == "zb" then
    return slide_position
  end

  return "zz"
end

--- Send navigation request to Slidev dev server.
---@param page integer
---@param force? boolean
---@param preserve_clicks? boolean
---@param initial_clicks? integer
local function navigate_to_page(page, force, preserve_clicks, initial_clicks)
  if not force and page == state.last_page then
    return
  end

  local is_same_page = page == state.last_page
  state.clicks_total = estimate_clicks_total(page)
  if initial_clicks ~= nil then
    state.clicks = initial_clicks
  else
    state.clicks = clicks.resolve_for_navigation(state.clicks, state.last_page, page, preserve_clicks)
  end
  state.last_page = page
  refresh_statusline()

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
  refresh_statusline()
end

---@return string[]|nil
local function get_active_slide_lines()
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

  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

--- Move the cursor to a slide and navigate the preview.
---@param target_page integer
---@param opts? table
---@param lines? string[]
local function move_to_page(target_page, opts, lines)
  lines = lines or get_active_slide_lines()
  if not lines then
    return
  end

  local target_line = parser.get_slide_content_start_line(lines, target_page)
  if not target_line then
    return
  end

  vim.api.nvim_win_set_cursor(0, { target_line, 0 })
  vim.cmd("normal! " .. resolve_slide_position())

  local initial_clicks = nil
  if opts and opts.enter_clicks == "max" then
    initial_clicks = control.resolve_previous_slide_clicks(estimate_clicks_total(target_page))
  end

  navigate_to_page(target_page, true, false, initial_clicks)
end

--- Move the cursor to another slide and navigate the preview.
---@param delta integer
---@param opts? table
local function move_slide(delta, opts)
  local lines = get_active_slide_lines()
  if not lines then
    return
  end

  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local current_page = parser.get_page_at_line(lines, cursor_line)
  move_to_page(current_page + delta, opts, lines)
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
  vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter", "BufEnter" }, {
    group = state.augroup,
    callback = function()
      apply_winbar(vim.api.nvim_get_current_win())
    end,
  })

  state.enabled = true
  apply_winbar(vim.api.nvim_get_current_win())
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

  clear_all_winbar()

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

local function refresh_clicks_total()
  local page = resolve_clicks_page()
  if not page then
    return false
  end

  state.clicks_total = estimate_clicks_total(page) or state.clicks_total
  return true
end

local function control_forward()
  if not refresh_clicks_total() then
    return
  end

  local action = control.resolve_forward_action(state.clicks, state.clicks_total)
  if action == "clicks_increment" then
    update_clicks(1)
  else
    move_slide(1)
  end
end

local function control_backward()
  if not refresh_clicks_total() then
    return
  end

  local action = control.resolve_backward_action(state.clicks)
  if action == "clicks_decrement" then
    update_clicks(-1)
  else
    move_slide(-1, { enter_clicks = "max" })
  end
end

local function handle_control_action(action, opts)
  if action == "next_slide" then
    move_slide(1)
  elseif action == "previous_slide" then
    move_slide(-1)
  elseif action == "first_slide" then
    move_to_page(1)
  elseif action == "last_slide" then
    local lines = get_active_slide_lines()
    if lines then
      move_to_page(parser.get_slide_count(lines), nil, lines)
    end
  elseif action == "goto_slide" and opts and opts.page then
    move_to_page(opts.page)
  elseif action == "move_slide" and opts and opts.delta then
    move_slide(opts.delta)
  elseif action == "forward" then
    control_forward()
  elseif action == "backward" then
    control_backward()
  end
end

local function redraw_control()
  -- Force statusline/winbar re-evaluation before flushing the screen so
  -- external bars (e.g. lualine) reflect control mode during getcharstr().
  refresh_statusline()
  if vim.api.nvim__redraw then
    vim.api.nvim__redraw({ cursor = true, flush = true })
  else
    vim.cmd("redraw")
  end
end

local function run_control_loop(actions)
  while true do
    local ok, key = pcall(vim.fn.getcharstr)
    if not ok or key == "" then
      return
    end

    local action, action_opts = control.action_for_input(actions, key, function()
      local read_ok, next_key = pcall(vim.fn.getcharstr)
      if not read_ok then
        return nil
      end
      return next_key
    end)
    if action == "exit" then
      return
    end
    if action then
      handle_control_action(action, action_opts)
      redraw_control()
    end
  end
end

--- Enter Slidev control mode.
local function cmd_control()
  if state.control_active then
    vim.notify("[slidev-preview] Control mode is already active", vim.log.levels.WARN)
    return
  end

  state.control_active = true
  redraw_control()

  local ok, err = pcall(run_control_loop, control.build_actions(config.control and config.control.keys or nil))

  state.control_active = false
  redraw_control()

  if not ok then
    vim.notify("[slidev-preview] Control mode aborted: " .. tostring(err), vim.log.levels.ERROR)
  end
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

  vim.api.nvim_set_hl(0, "SlidevPreviewWinbar", { default = true, link = "Comment" })
  vim.api.nvim_set_hl(0, "SlidevPreviewControl", { default = true, link = "IncSearch" })

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
  vim.api.nvim_create_user_command("SlidevPreviewControl", cmd_control, { desc = "Enter Slidev preview control mode" })
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
