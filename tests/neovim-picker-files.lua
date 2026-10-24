local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root .. "/dotfiles/dot_config/nvim")
vim.opt.runtimepath:append(vim.fn.stdpath("data") .. "/site/pack/core/opt/snacks.nvim")
vim.o.lines = 60
vim.o.columns = 160
vim.o.hidden = true
vim.g.mapleader = " "
vim.pack.add = function() end
package.loaded["lz.n"] = { load = function() end, trigger_load = function() end }
local directory = vim.fn.tempname() .. " picker project"
vim.fn.mkdir(directory .. "/nested", "p")
directory = vim.uv.fs_realpath(directory)
package.loaded["project"] = { get_project_root = function() return directory end }
for _, name in ipairs({ "before.ts", "modified.ts", "stable.ts" }) do
  vim.fn.writefile({ "original " .. name }, directory .. "/" .. name)
end
vim.cmd.cd(vim.fn.fnameescape(directory .. "/nested"))
dofile(root .. "/dotfiles/dot_config/nvim/plugin/50_picker.lua")
local Snacks = require("snacks")

local function edit(name)
  vim.cmd.edit(vim.fn.fnameescape(directory .. "/" .. name))
  return vim.api.nvim_get_current_buf()
end
local original = edit("before.ts")
local modified = edit("modified.ts")
vim.api.nvim_buf_set_lines(modified, 0, -1, false, { "unsaved edits" })
local draft = edit("draft.ts")
vim.api.nvim_buf_set_lines(draft, 0, -1, false, { "unsaved new file" })
edit("stable.ts")
vim.v.oldfiles = { directory .. "/before.ts", directory .. "/modified.ts" }
assert(vim.uv.fs_rename(directory .. "/before.ts", directory .. "/after.ts"))
assert(vim.uv.fs_rename(directory .. "/modified.ts", directory .. "/modified-moved.ts"))

local function settle(picker)
  assert(vim.wait(3000, function() return picker.shown and not picker:is_active() end, 10), "Picker did not finish finding files")
end
local function files(picker)
  local found = {}
  for _, item in ipairs(picker:items()) do
    found[Snacks.picker.util.path(item)] = true
  end
  return found
end
local function open(keys)
  vim.fn.maparg(keys, "n", false, true).callback()
  local picker
  assert(vim.wait(3000, function()
    picker = Snacks.picker.get()[1]
    return picker ~= nil
  end, 10), "Project file picker did not open")
  settle(picker)
  return picker
end

local ok, err = xpcall(function()
  for _, keys in ipairs({ " ff", " уу" }) do
    local picker = open(keys)
    local found = files(picker)
    assert(not found[directory .. "/before.ts"], "Project search still includes an old buffer path after mv")
    assert(found[directory .. "/after.ts"], "Project search cannot find the moved file")
    assert(found[directory .. "/modified.ts"] and found[directory .. "/draft.ts"], "Project search hides unsaved buffer contents")
    assert(found[directory .. "/modified-moved.ts"], "Moved modified file is missing from disk results")
    assert(vim.bo[modified].modified and vim.bo[draft].modified)
    assert(vim.api.nvim_buf_is_valid(original), "Filtering deleted the original buffer")
    assert(vim.api.nvim_buf_get_lines(original, 0, 1, false)[1] == "original before.ts")
    assert(vim.uv.fs_rename(directory .. "/stable.ts", directory .. "/refreshed.ts"))
    for _, win in ipairs({ picker.input.win, picker.list.win }) do
      local modes = win == picker.input.win and { "i", "n" } or { "n" }
      for _, mode in ipairs(modes) do
        vim.api.nvim_set_current_win(win.win)
        local mapping = vim.fn.maparg("<F5>", mode, false, true)
        assert(type(mapping.callback) == "function", "Missing picker refresh shortcut: " .. mode)
        mapping.callback()
        settle(picker)
        local refreshed = files(picker)
        assert(not refreshed[directory .. "/stable.ts"] and refreshed[directory .. "/refreshed.ts"], "Refresh did not reload moved files")
      end
    end
    picker:close()
    assert(vim.uv.fs_rename(directory .. "/refreshed.ts", directory .. "/stable.ts"))
  end
  local buffer_picker = open(" bb")
  assert(files(buffer_picker)[directory .. "/before.ts"], "Buffer picker lost access to the old buffer")
  buffer_picker:close()
  print("PASS: project search drops moved clean buffers, preserves unsaved contents, scans from nested cwd, refreshes with F5 in input/list, and retains buffer access; Latin/Russian leader equivalence")
end, debug.traceback)
for _, picker in ipairs(Snacks.picker.get()) do picker:close() end
vim.cmd.cd(vim.fn.fnameescape(root))
vim.fn.delete(directory, "rf")
if not ok then error(err) end
vim.cmd("qa!")
