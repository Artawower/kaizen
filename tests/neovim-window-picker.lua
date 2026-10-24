local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root .. "/dotfiles/dot_config/nvim")
vim.opt.runtimepath:append(vim.fn.stdpath("data") .. "/site/pack/core/opt/nvim-window-picker")
vim.o.lines = 80
vim.o.columns = 200
vim.g.mapleader = " "
local configure
vim.pack.add = function(specs)
  for _, spec in ipairs(specs) do
    if spec.src == "https://github.com/s1n7ax/nvim-window-picker" then configure = spec.data.after end
  end
end
package.loaded["lz.n"] = { load = function() end, trigger_load = function() end }
dofile(root .. "/dotfiles/dot_config/nvim/plugin/20_keymaps.lua")
configure()
local picker = require("window-picker")
local candidates, draws, notification
local hint = {
  set_config = function() end,
  draw = function(_, windows) candidates = windows; draws = (draws or 0) + 1 end,
  clear = function() end,
}
vim.fn.getchar = function() return string.byte("F") end
vim.notify = function(message) notification = message end
picker.setup({ hint = hint, show_prompt = false })
local current = vim.api.nvim_get_current_win()
vim.api.nvim_buf_set_name(0, "/tmp/kaizen-window-picker-current.ts")
local function split(buftype)
  vim.cmd("botright 2new")
  local win = vim.api.nvim_get_current_win()
  vim.bo.buftype = buftype or ""
  return win
end
local unnamed = split()
local readonly = split()
vim.api.nvim_buf_set_name(0, "/tmp/kaizen-window-picker-readonly.ts")
vim.bo.readonly = true
local expected = { unnamed, readonly }
for _, buftype in ipairs({ "nofile", "nowrite", "acwrite", "prompt", "help", "quickfix" }) do
  split(buftype)
end
local terminal = split()
vim.api.nvim_open_term(vim.api.nvim_win_get_buf(terminal), {})
local preview = split()
vim.wo.previewwindow = true
local floats = {}
for _, focusable in ipairs({ true, false }) do
  for _, buf in ipairs({ vim.api.nvim_win_get_buf(readonly), vim.api.nvim_create_buf(false, true) }) do
    floats[#floats + 1] = vim.api.nvim_open_win(buf, false, {
      relative = "editor", row = 1, col = 1, width = 20, height = 2, focusable = focusable,
    })
  end
end
vim.api.nvim_set_current_win(current)
local picked = picker.pick_window()
table.sort(candidates)
table.sort(expected)
assert(vim.deep_equal(candidates, expected), "Picker includes utility/floating windows: " .. vim.inspect(candidates))
assert(vim.list_contains(expected, picked), "Picker selected a non-editor window")
for _, mode in ipairs({ "n", "i" }) do
  for _, keys in ipairs({ "<D-.>", "<D-ю>" }) do
    vim.api.nvim_set_current_win(current)
    local mapping = vim.fn.maparg(keys, mode, false, true)
    assert(type(mapping.callback) == "function", "Missing picker shortcut: " .. mode .. " " .. keys)
    mapping.callback()
    assert(vim.list_contains(expected, vim.api.nvim_get_current_win()), "Shortcut focused a utility window")
  end
end
vim.api.nvim_set_current_win(floats[1])
picker.pick_window()
assert(vim.list_contains(candidates, current), "Picker cannot return from a popup to an editor")
assert(not vim.list_contains(candidates, floats[1]), "Focused floating window is still a candidate")
vim.api.nvim_set_current_win(current)
vim.api.nvim_win_close(readonly, true)
local previous_draws = draws
assert(picker.pick_window() == unnamed, "Single real editor was not auto-selected")
assert(draws == previous_draws, "Single editor unnecessarily opened the picker")
vim.api.nvim_win_close(unnamed, true)
local mapping = vim.fn.maparg("<D-.>", "n", false, true)
mapping.callback()
assert(vim.api.nvim_get_current_win() == current, "No-candidate selection changed focus")
assert(notification == "No windows left to pick after filtering", "No-candidate selection did not exit cleanly")
assert(vim.api.nvim_win_is_valid(preview), "Picker closed a utility window")
print("PASS: real picker excludes floating, terminal, help, quickfix, prompt, scratch and preview windows; unnamed/readonly editors remain; normal/insert Russian aliases; zero/one/multiple candidates")
vim.cmd("qa!")
