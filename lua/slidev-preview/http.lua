local M = {}

--- Send an HTTP POST request (fire-and-forget) using vim.loop TCP.
---@param host string
---@param port integer
---@param path string
---@param json_body string JSON-encoded body
function M.post(host, port, path, json_body)
  local uv = vim.uv or vim.loop
  local client = uv.new_tcp()

  client:connect(host, port, function(err)
    if err then
      client:close()
      return
    end

    local request = string.format(
      "POST %s HTTP/1.1\r\nHost: %s:%d\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s",
      path, host, port, #json_body, json_body
    )

    client:write(request, function(write_err)
      if write_err then
        client:close()
        return
      end
      -- Read response to complete the HTTP transaction, then close
      client:read_start(function(_, chunk)
        if chunk == nil then
          client:close()
        end
      end)
    end)
  end)
end

return M
