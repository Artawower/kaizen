local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root .. "/dotfiles/dot_config/nvim")
for _, path in ipairs(vim.fn.globpath(vim.fn.stdpath("data") .. "/site/pack/*/opt", "*", false, true)) do
  vim.opt.runtimepath:append(path)
end
vim.cmd.runtime("plugin/filetypes.lua")

require("blink.cmp").setup({ fuzzy = { implementation = "lua" } })
local plugins = {}
vim.pack.add = function(specs)
  for _, spec in ipairs(specs) do
    local src = type(spec) == "string" and spec or spec.src
    plugins[src] = true
    if src == "https://github.com/windwp/nvim-autopairs" then
      spec.data.after()
    end
  end
end
dofile(root .. "/dotfiles/dot_config/nvim/plugin/40_editing.lua")

local function type_keys(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
  vim.wait(20)
end

local function check(filetype, initial, column, keys, expected)
  vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
  vim.bo.filetype = filetype
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { initial })
  vim.api.nvim_win_set_cursor(0, { 1, column })
  type_keys(keys)
  local actual = vim.api.nvim_get_current_line()
  assert(actual == expected, filetype .. ": expected " .. expected .. ", got " .. actual)
end

for _, filetype in ipairs({ "html", "javascriptreact", "typescriptreact" }) do
  check(filetype, "<div", 3, "a><Esc>", "<div></div>")
  check(filetype, "<div></div>", 2, "ciwspan<Esc>", "<span></span>")
  check(filetype, '<div class=""></div>', 12, "i><Esc>", '<div class=">"></div>')
  print("PASS: " .. filetype .. " tag closing and synchronized renaming")
end
check("html", "<input", 5, "a><Esc>", "<input>")
check("typescriptreact", "<Button /", 8, "a><Esc>", "<Button />")
check("typescriptreact", "const n = 1 ", 11, "a> 0<Esc>", "const n = 1 > 0")
check("typescriptreact", "", 0, 'i(<Esc>', "()")
check("typescriptreact", "", 0, 'i"<Esc>', '""')
assert(plugins["https://github.com/windwp/nvim-ts-autotag"], "Autotag is missing from the plugin catalog")
print("PASS: void/self-closing tags, comparisons, and existing bracket/quote pairing")
vim.cmd("qa!")
