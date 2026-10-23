local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root .. "/dotfiles/dot_config/nvim")
for _, plugin in ipairs({ "snacks.nvim", "blink.cmp", "friendly-snippets", "lz.n" }) do
  local paths = vim.fn.globpath(vim.fn.stdpath("data") .. "/site/pack/*/opt", plugin, false, true)
  assert(#paths > 0, "Install the Neovim plugin first: " .. plugin)
  vim.opt.runtimepath:append(paths[1])
end

local directory = vim.fn.tempname()
vim.fn.mkdir(directory, "p")
local function fixture(filetype, snippets)
  vim.fn.writefile({ vim.json.encode(snippets) }, directory .. "/" .. filetype .. ".json")
end
fixture("lua", {
  local_snippet = {
    prefix = { "kaizen_local", "kaizen_alias" },
    description = "Local snippet with placeholders",
    body = { "local ${1:name} = '${TM_FILENAME_BASE}'", "$0" },
  },
})
fixture("all", {
  global_snippet = { prefix = "kaizen_global", body = "global ${1:value}$0" },
})
fixture("javascript", {
  extended_snippet = { prefix = "kaizen_extended", body = "extended ${1:value}$0" },
})

local ok, err = xpcall(function()
  require("blink.cmp").setup({
    fuzzy = { implementation = "lua" },
    sources = {
      default = { "snippets" },
      providers = {
        snippets = { opts = { search_paths = { directory }, extended_filetypes = { lua = { "javascript" } } } },
      },
    },
  })
  vim.g.mapleader = " "
  vim.pack.add = function() end
  dofile(root .. "/dotfiles/dot_config/nvim/plugin/20_keymaps.lua")
  dofile(root .. "/dotfiles/dot_config/nvim/plugin/50_picker.lua")
  local Snacks = require("snacks")
  local buffer = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_name(buffer, directory .. "/original.lua")
  vim.bo.filetype = "lua"
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "before after" })
  vim.api.nvim_win_set_cursor(0, { 1, 7 })

  local function open(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>" .. keys, true, false, true), "xt", false)
    local picker
    assert(vim.wait(3000, function()
      picker = Snacks.picker.get()[1]
      return picker and picker.shown and not picker:is_active()
    end, 10), "Snippet picker did not open")
    return picker
  end

  local picker = open(" fs")
  local items = {}
  for _, item in ipairs(picker:items()) do
    items[item.text:match("^(%S+)")] = item
  end
  assert(items.kaizen_local and items.kaizen_alias and items.kaizen_global and items.kaizen_extended)
  assert(#picker:items() > 25, "Friendly snippets were not included")
  local item = items.kaizen_local
  assert(item.text:find("Local snippet with placeholders", 1, true))
  assert(item.preview.ft == "lua" and item.preview.text:find("original", 1, true))
  assert(not picker.layout:is_hidden("preview"), "Snippet preview must be visible")
  picker.opts.confirm(picker, item)
  assert(vim.wait(1000, function()
    return vim.api.nvim_buf_get_lines(buffer, 0, 1, false)[1] == "before local name = 'original'"
  end, 10), "Snippet was not inserted at the original cursor")
  assert(vim.api.nvim_get_current_buf() == buffer, "Snippet inserted into the picker instead of the source")
  assert(vim.snippet.active(), "Snippet placeholders are not active")
  vim.snippet.stop()
  vim.cmd.stopinsert()
  print("PASS: current, global, extended, local and friendly snippets; preview; variables; expansion and placeholders")

  local before = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  picker = open(" ув")
  picker:close()
  vim.wait(50)
  assert(vim.deep_equal(before, vim.api.nvim_buf_get_lines(buffer, 0, -1, false)))
  print("PASS: Russian shortcut equivalence and cancellation without buffer edits")

  vim.bo.filetype = "kaizen_unknown"
  picker = open(" fs")
  for _, candidate in ipairs(picker:items()) do
    assert(not candidate.text:match("^kaizen_local"), "Filetype-specific snippet leaked")
  end
  assert(vim.iter(picker:items()):any(function(candidate) return candidate.text:match("^kaizen_global") end))
  picker:close()
  vim.wait(50)
  print("PASS: filetype filtering keeps global snippets")

  local source = require("blink.cmp.sources.lib").get_provider_by_id("snippets")
  source.module.registry.config.global_snippets = {}
  vim.bo.filetype = "kaizen_empty"
  vim.api.nvim_feedkeys(" fs", "xt", false)
  vim.wait(100)
  assert(#Snacks.picker.get() == 0, "Empty snippet picker did not close cleanly")
  assert(vim.v.errmsg == "", vim.v.errmsg)
  print("PASS: no available snippets is handled without errors")
end, debug.traceback)
vim.fn.delete(directory, "rf")
assert(ok, err)
vim.cmd("qa!")
