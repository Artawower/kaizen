local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root .. "/dotfiles/dot_config/nvim")
vim.g.mapleader = " "
vim.pack.add = function() end
package.loaded["lz.n"] = { load = function() end, trigger_load = function() end }
local copied
vim.fn.setreg = function(register, value)
  assert(register == "+")
  copied = value
end
vim.notify = function() end
dofile(root .. "/dotfiles/dot_config/nvim/plugin/20_keymaps.lua")
dofile(root .. "/dotfiles/dot_config/nvim/plugin/70_lsp.lua")
dofile(root .. "/dotfiles/dot_config/nvim/plugin/95_ai.lua")
local directory = vim.fn.tempname()
vim.fn.mkdir(directory .. "/.jj", "p")
vim.fn.mkdir(directory .. "/src", "p")
local namespace = vim.api.nvim_create_namespace("ContextCopyTest")
local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
end
local ok, err = xpcall(function()
  vim.cmd.lcd(directory .. "/src")
  vim.api.nvim_buf_set_name(0, directory .. "/src/container.html")
  local lines = { '<div class="container">', "  @if (title()) {", "    <h3>{{title()}}</h3>", "  }", "</div>" }
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  for _, key in ipairs({ " ac", " фс" }) do
    copied = nil
    feed("gg0" .. key .. "<Esc>")
    assert(copied == "src/container.html, line numbers 1:1\n\n" .. lines[1], "Normal context copy failed: " .. tostring(copied))
    feed("gg03lV2j" .. key .. "<Esc>")
    assert(copied == "src/container.html, line numbers 1:3\n\n" .. table.concat(lines, "\n", 1, 3), "Linewise selection was truncated: " .. tostring(copied))
    feed("gg0v2l" .. key .. "<Esc>")
    assert(copied == "src/container.html, line numbers 1:1\n\n<di", tostring(copied))
    feed("gg02lvhh" .. key .. "<Esc>")
    assert(copied == "src/container.html, line numbers 1:1\n\n<di", "Reverse selection failed")
    feed("gg0<C-v>j2l" .. key .. "<Esc>")
    assert(copied == "src/container.html, line numbers 1:2\n\n<di\n  @", "Blockwise selection failed: " .. tostring(copied))
  end
  vim.o.selection = "exclusive"
  feed("gg0v2l ac<Esc>")
  assert(copied == "src/container.html, line numbers 1:1\n\n<d", "Exclusive selection failed")
  vim.o.selection = "inclusive"
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "фя🙂", "", "tail" })
  feed("gg0v2l ac<Esc>")
  assert(copied == "src/container.html, line numbers 1:1\n\nфя🙂", "Unicode selection was truncated")
  feed("2G ac<Esc>")
  assert(copied == "src/container.html, line numbers 2:2\n\n", "Empty line copy failed")
  vim.diagnostic.set(namespace, 0, {
    { lnum = 0, col = 0, end_col = 2, message = "Selected problem", severity = vim.diagnostic.severity.ERROR },
    { lnum = 2, col = 0, end_col = 2, message = "Outside problem", severity = vim.diagnostic.severity.WARN },
  })
  feed("gg0V ac<Esc>")
  assert(copied:find("1:1 [ERROR] Selected problem", 1, true), "Selected diagnostic was lost")
  assert(not copied:find("Outside problem", 1, true), "Unrelated diagnostic was included")
  feed("gg0VN<Esc>")
  assert(copied:find("Selected problem", 1, true), "Existing visual N shortcut was lost")
  local commands = {}
  for _, action in ipairs({ "Start", "Comment", "Done" }) do
    vim.api.nvim_create_user_command("Postilla" .. action, function() commands[#commands + 1] = action end, {})
  end
  for _, keys in ipairs({ " rs", " rc", " rd", " ыв", " ыс", " ып" }) do
    feed(keys)
  end
  assert(vim.deep_equal(commands, { "Start", "Comment", "Done", "Start", "Comment", "Done" }), "Postilla actions were lost")
  print("PASS: Latin/Russian context copying; normal, characterwise, linewise, blockwise, reversed and exclusive selections; Unicode; diagnostics; Postilla")
end, debug.traceback)
vim.cmd.lcd(root)
vim.fn.delete(directory, "rf")
assert(ok, err)
vim.cmd("qa!")
