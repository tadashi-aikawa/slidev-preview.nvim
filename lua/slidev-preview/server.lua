local M = {}

local job_id = nil
local is_ready = false
local browser_opened = false

function M.is_running()
  return job_id ~= nil
end

function M.is_server_ready()
  return is_ready
end

--- Start the Slidev dev server.
---@param opts { port: integer, slidev_bin: string, open_browser: boolean }
function M.start(opts)
  if job_id then
    vim.notify("[slidev-preview] Server is already running", vim.log.levels.WARN)
    return
  end

  is_ready = false
  browser_opened = false

  local cmd = opts.slidev_bin .. " --port " .. opts.port .. " --remote --no-open"

  job_id = vim.fn.jobstart(cmd, {
    cwd = vim.fn.getcwd(),
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        if not is_ready and (line:match("http://localhost") or line:match("ready in")) then
          is_ready = true
          if opts.open_browser and not browser_opened then
            browser_opened = true
            vim.schedule(function()
              M.open_browser(opts.port)
            end)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      for _, line in ipairs(data) do
        if not is_ready and (line:match("http://localhost") or line:match("ready in")) then
          is_ready = true
          if opts.open_browser and not browser_opened then
            browser_opened = true
            vim.schedule(function()
              M.open_browser(opts.port)
            end)
          end
        end
      end
    end,
    on_exit = function()
      job_id = nil
      is_ready = false
    end,
  })

  if job_id <= 0 then
    vim.notify("[slidev-preview] Failed to start server", vim.log.levels.ERROR)
    job_id = nil
    return
  end

  vim.notify("[slidev-preview] Starting Slidev dev server on port " .. opts.port)
end

--- Stop the Slidev dev server.
function M.stop()
  if not job_id then
    vim.notify("[slidev-preview] Server is not running", vim.log.levels.WARN)
    return
  end

  vim.fn.jobstop(job_id)
  job_id = nil
  is_ready = false
  browser_opened = false
  vim.notify("[slidev-preview] Server stopped")
end

--- Open the browser to a specific page.
---@param port integer
---@param page? integer
function M.open_browser(port, page)
  local url = "http://localhost:" .. port
  if page then
    url = url .. "/" .. page
  end

  if vim.ui.open then
    vim.ui.open(url)
  else
    -- Fallback for Neovim < 0.10
    local cmd
    if vim.fn.has("mac") == 1 then
      cmd = { "open", url }
    elseif vim.fn.has("unix") == 1 then
      cmd = { "xdg-open", url }
    else
      cmd = { "cmd.exe", "/c", "start", url }
    end
    vim.fn.jobstart(cmd, { detach = true })
  end
end

return M
