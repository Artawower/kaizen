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

vim.opt.runtimepath:append(vim.fn.stdpath("data") .. "/site/pack/core/opt/snacks.nvim")
local snacks = require("snacks")
snacks.setup({ picker = { enabled = true } })
local sidebar = snacks.picker.pick({
  title = "JJ Status",
  items = { { text = "modified.ts" }, { text = "added.ts" } },
  format = "text",
  preview = function() end,
  auto_close = false,
  jump = { close = false },
  layout = { preset = "sidebar", preview = "main", layout = { position = "left", width = 35 } },
})
assert(vim.wait(1000, function() return sidebar.list.win:valid() and sidebar.input.win:valid() end), "Sidebar did not open")
local list = sidebar.list.win.win
local input = sidebar.input.win.win
assert(vim.bo[sidebar.list.win.buf].filetype == "snacks_picker_list")
assert(vim.bo[sidebar.input.win.buf].filetype == "snacks_picker_input")
vim.cmd("stopinsert")
vim.api.nvim_set_current_win(current)
candidates = nil
local selected = picker.pick_window({ filter_rules = { autoselect_one = false } })
assert(selected == list, "Sidebar list cannot be selected: " .. tostring(selected))
assert(vim.deep_equal(candidates, { list }), "Sidebar list is missing or input was included: " .. vim.inspect(candidates))
mapping.callback()
assert(vim.api.nvim_get_current_win() == list, "Window jump did not focus the sidebar list")
assert(vim.api.nvim_get_current_win() ~= input, "Window jump focused the input")
sidebar:close()
print("PASS: actual Snacks sidebar list is selectable; input and layout containers are excluded")

vim.opt.runtimepath:append(vim.fn.stdpath("data") .. "/site/pack/core/opt/oil.nvim")
local oil = require("oil")
oil.setup({ default_file_explorer = false })
vim.api.nvim_set_current_win(current)
local oil_window = split()
local ready = false
oil.open(root .. "/tests", {}, function() ready = true end)
assert(vim.wait(2000, function() return ready end), "Oil directory did not load")
local oil_buffer = vim.api.nvim_win_get_buf(oil_window)
assert(vim.bo[oil_buffer].filetype == "oil" and vim.bo[oil_buffer].buftype == "acwrite")
local oil_float = vim.api.nvim_open_win(oil_buffer, false, {
  relative = "editor", row = 1, col = 1, width = 20, height = 2,
})
vim.api.nvim_win_set_buf(preview, oil_buffer)
vim.api.nvim_set_current_win(current)
candidates = nil
local oil_selected = picker.pick_window({ filter_rules = { autoselect_one = false } })
assert(oil_selected == oil_window, "Actual Oil split cannot be selected: " .. tostring(oil_selected))
assert(vim.deep_equal(candidates, { oil_window }), "Oil float or preview was included: " .. vim.inspect(candidates))
picker.setup({ filter_rules = { autoselect_one = true } })
for _, mode in ipairs({ "n", "i" }) do
  for _, keys in ipairs({ "<D-.>", "<D-ю>" }) do
    vim.api.nvim_set_current_win(current)
    vim.fn.maparg(keys, mode, false, true).callback()
    assert(vim.api.nvim_get_current_win() == oil_window, "Shortcut did not focus Oil: " .. mode .. " " .. keys)
    vim.fn.maparg(keys, mode, false, true).callback()
    assert(vim.api.nvim_get_current_win() == current, "Shortcut did not return from Oil to the editor")
  end
end
vim.api.nvim_win_close(oil_float, true)
print("PASS: actual Oil split is selectable in both directions with Latin/Russian shortcuts; Oil floats and previews remain excluded")
vim.cmd("qa!")
