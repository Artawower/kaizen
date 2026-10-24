local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root .. "/dotfiles/dot_config/nvim")
vim.g.mapleader = " "
local plugins = {}
vim.pack.add = function(specs)
  for _, spec in ipairs(specs) do
    if type(spec) == "table" then plugins[spec.src] = spec end
  end
end
package.loaded["lz.n"] = { load = function() end, trigger_load = function() end }
for _, name in ipairs({ "snacks", "nvim-ts-autotag", "mini.surround", "bento", "blink.cmp", "auto-session", "project", "octo" }) do
  package.loaded[name] = { setup = function() end, get_lsp_capabilities = function(caps) return caps end }
end
package.loaded["bento.api"] = setmetatable({ actions = {} }, {
  __index = function() return function() end end,
})
for _, file in ipairs({ "20_keymaps", "40_editing", "50_picker", "60_projects", "70_lsp", "80_vcs", "90_debug", "95_ai", "98_notes" }) do
  dofile(root .. "/dotfiles/dot_config/nvim/plugin/" .. file .. ".lua")
end

local aliases = {}
local latin = vim.fn.split("`qwfpgjluy;[]arstdhneio'zxcvbkm,.", "\\zs")
local russian = vim.fn.split("ёйцукенгшщзхъфывапролджэячсмитьбю", "\\zs")
assert(#latin == #russian)
for i, key in ipairs(latin) do
  aliases[key] = russian[i]
  if key:match("%a") then aliases[key:upper()] = vim.fn.toupper(russian[i]) end
end
for key, value in pairs({ ["~"] = "Ё", [":"] = "З", ["{"] = "Х", ["}"] = "Ъ", ['"'] = "Э", ["<"] = "Б", [">"] = "Ю" }) do
  aliases[key] = value
end
local function translate(keys)
  return (keys:gsub(".", aliases))
end
local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
end
local inventory = {}
for _, mode in ipairs({ "n", "x" }) do
  for _, mapping in ipairs(vim.api.nvim_get_keymap(mode)) do
    if mapping.lhs:sub(1, 1) == " " and not mapping.lhs:find("[\128-\255]") then
      local russian_keys = translate(mapping.lhs)
      local alias = vim.fn.maparg(russian_keys, mode, false, true)
      assert(alias.callback == mapping.callback
        and vim.api.nvim_replace_termcodes(alias.rhs or "", true, false, true)
          == vim.api.nvim_replace_termcodes(mapping.rhs or "", true, false, true)
        and alias.desc == mapping.desc,
        "Missing or different Russian action: " .. mode .. " / " .. mapping.lhs .. " / " .. russian_keys .. " / " .. vim.inspect({ mapping = mapping, alias = alias }))
      inventory[#inventory + 1] = { mode = mode, latin = mapping.lhs, russian = russian_keys }
    end
  end
end
assert(#inventory > 80, "Leader inventory is unexpectedly small: " .. #inventory)
local hit
for index, entry in ipairs(inventory) do
  for _, key in ipairs({ entry.latin, entry.russian }) do
    vim.keymap.set(entry.mode, key, function() hit = index end)
  end
end
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "selection" })
for index, entry in ipairs(inventory) do
  for _, key in ipairs({ entry.latin, entry.russian }) do
    hit = nil
    feed("<Esc>" .. (entry.mode == "x" and "v" or "") .. key .. "<Esc>")
    assert(hit == index, "Leader input failed: " .. entry.mode .. " / " .. key)
  end
end
feed("gg0iфсЫВЯ🙂<Esc>")
assert(vim.api.nvim_get_current_line() == "фсЫВЯ🙂selection", "Language aliases changed inserted text")
print("PASS: " .. #inventory .. " effective leader/mode bindings, Latin/Russian input, Shift and punctuation; text insertion unchanged")

local oil_keys, sorted
package.loaded.oil = {
  setup = function(opts) oil_keys = opts.keymaps end,
  set_sort = function(order) sorted = order end,
}
plugins["https://github.com/stevearc/oil.nvim"].data.after()
for key, mapping in pairs(oil_keys) do
  vim.keymap.set("n", key, mapping.callback, { buffer = 0 })
end
for _, pair in ipairs({ { " sd", " вп" }, { " sn", " во" } }) do
  feed(pair[1])
  local expected = sorted
  sorted = nil
  feed(pair[2])
  assert(vim.deep_equal(sorted, expected), "Oil sorting differs between layouts")
end
print("PASS: lazy buffer-local Oil leader aliases")
vim.cmd("qa!")
