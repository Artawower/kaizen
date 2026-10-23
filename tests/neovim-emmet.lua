local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root .. "/dotfiles/dot_config/nvim")
for _, path in ipairs(vim.fn.globpath(vim.fn.stdpath("data") .. "/site/pack/*/opt", "*", false, true)) do
  vim.opt.runtimepath:append(path)
end
vim.cmd.runtime("plugin/filetypes.lua")
require("blink.cmp").setup({ enabled = function() return false end, fuzzy = { implementation = "lua" } })
vim.pack.add = function(specs)
  for _, spec in ipairs(specs) do
    local src = type(spec) == "string" and spec or spec.src
    if src == "https://github.com/mattn/emmet-vim" then
      vim.cmd.runtime("plugin/emmet.vim")
    end
  end
end
vim.g.mapleader = " "
dofile(root .. "/dotfiles/dot_config/nvim/plugin/20_keymaps.lua")
dofile(root .. "/dotfiles/dot_config/nvim/plugin/40_editing.lua")
dofile(root .. "/dotfiles/dot_config/nvim/plugin/50_picker.lua")

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
  vim.wait(20)
end
local function buffer(filetype, text)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.bo.filetype = filetype
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text })
  vim.api.nvim_win_set_cursor(0, { 1, math.max(#text - 1, 0) })
  return buf
end

for _, key in ipairs({ "<D-e>", "<D-л>" }) do
  for _, mode in ipairs({ "n", "i" }) do
    for _, filetype in ipairs({ "html", "javascriptreact", "typescriptreact" }) do
      buffer(filetype, "div.box")
      feed((mode == "i" and "a" or "") .. key .. "<Esc>")
      local attribute = filetype == "html" and "class" or "className"
      assert(vim.api.nvim_get_current_line() == '<div ' .. attribute .. '="box"></div>', filetype .. "/" .. mode .. "/" .. key)
    end
    buffer("css", ".box {m10}")
    vim.api.nvim_win_set_cursor(0, { 1, mode == "i" and 8 or 9 })
    feed((mode == "i" and "a" or "") .. key .. "<Esc>")
    assert(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false)):gsub("%s", "") == ".box{margin:10px;}", "CSS Emmet expansion failed: " .. vim.inspect(vim.api.nvim_buf_get_lines(0, 0, -1, false)))
  end
  buffer("html", "hello")
  feed("0v$" .. key .. "div<CR><Esc>")
  assert(vim.api.nvim_get_current_line() == "<div>hello</div>", "Visual Emmet wrapping failed")
end
assert(vim.fn.maparg("<C-y>,", "i") == "", "Unexpected default Emmet shortcuts")
assert(vim.fn.maparg("<D-f>", "n", false, true).desc == "Find in buffer", "Super+F search was changed")
print("PASS: Latin/Russian Emmet shortcuts in normal, insert, and visual modes; HTML, JSX, TSX, and CSS; existing search preserved")

for _, key in ipairs({ "<D-w>", "<D-ц>" }) do
  for _, mode in ipairs({ "n", "i", "x" }) do
    local buf = buffer("text", "unsaved content")
    local original = vim.api.nvim_get_current_win()
    vim.cmd.vsplit()
    local split = vim.api.nvim_get_current_win()
    feed((mode == "i" and "i" or mode == "x" and "v" or "") .. key .. "<Esc>")
    assert(not vim.api.nvim_win_is_valid(split) and vim.api.nvim_win_is_valid(original), "Wrong split was closed")
    assert(vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted and vim.bo[buf].modified, "Closing a split deleted its buffer or edits")
    assert(vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1] == "unsaved content")
    assert(vim.fn.maparg(key, mode, false, true).rhs == "<Cmd>close<CR>" or vim.fn.maparg(key, mode, false, true).rhs == "<cmd>close<CR>")
  end
end
print("PASS: Latin/Russian close-split shortcuts preserve the buffer and unsaved content")
vim.cmd("qa!")
