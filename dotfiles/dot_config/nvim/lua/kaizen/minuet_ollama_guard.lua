local M = {}
local uv = vim.uv or vim.loop

function M.setup()
  local config = require("minuet").config
  local ignored_filetypes = config.virtualtext.auto_trigger_ignore_ft or {}
  local model_name = config.provider_options.openai_fim_compatible.model
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
    vim.system({
      "curl",
      "--silent",
      "--fail",
      "--max-time",
      "1",
      "http://127.0.0.1:11434/api/tags",
    }, { text = true }, function(response)
      local model_available = false
      if response.code == 0 then
        local ok, result = pcall(vim.json.decode, response.stdout)
        if ok and type(result) == "table" and type(result.models) == "table" then
          for _, model in ipairs(result.models) do
            if model.name == model_name or model.model == model_name then
              model_available = true
              break
            end
          end
        end
      end

      vim.schedule(function()
        checking = false
        available = model_available
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
