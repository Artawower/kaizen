local M = {}
local uv = vim.uv or vim.loop

function M.setup()
  local config = require("minuet").config
  local ignored_filetypes = config.virtualtext.auto_trigger_ignore_ft or {}
  local available = false
  local checking = false

  local function update_buffer(buf)
    if not vim.api.nvim_buf_is_loaded(buf) then
      return
    end

    local filetype = vim.bo[buf].filetype
    vim.b[buf].minuet_virtual_text_auto_trigger = available
      and filetype ~= ""
      and not vim.tbl_contains(ignored_filetypes, filetype)
  end

  local function update()
    config.notify = available and "warn" or false
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      update_buffer(buf)
    end
  end

  local function check()
    if checking then
      return
    end

    checking = true
    local client = uv.new_tcp()
    client:connect("127.0.0.1", 11434, function(err)
      client:close()
      checking = false
      vim.schedule(function()
        available = not err
        update()
      end)
    end)
  end

  update()
  local group = vim.api.nvim_create_augroup("KaizenMinuetOllamaGuard", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    callback = function(event)
      update_buffer(event.buf)
    end,
  })

  local timer = uv.new_timer()
  timer:start(0, 5000, vim.schedule_wrap(check))
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      if not timer:is_closing() then
        timer:stop()
        timer:close()
      end
    end,
  })
end

return M
