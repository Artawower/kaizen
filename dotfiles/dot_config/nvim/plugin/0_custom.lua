vim.api.nvim_create_user_command("LuaEval", function()
  vim.ui.input({ prompt = "Lua> " }, function(code)
    if not code or code == "" then
      return
    end

    local fn, err = load(code)
    if not fn then
      return vim.notify(err, vim.log.levels.ERROR)
    end

    local ok, result = pcall(fn)
    if not ok then
      return vim.notify(result, vim.log.levels.ERROR)
    end

    if result ~= nil then
      vim.print(result)
    end
  end)
end, {})
