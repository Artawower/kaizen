vim.pack.add({
  { src = "https://github.com/wsdjeg/hop.nvim" },
})

local map = vim.keymap.set

require("hop").setup({
  keys = "arstneioqwfpghjluyzxcvbkm",
})

-- vim.keymap.set({ "n", "x", "o" }, "f", "<cmd>HopWord<CR>", {
--   desc = "Jump to word",
-- })

local function hop_word_select()
  -- Cancel previous Visual/operator state
  vim.cmd("normal! \27")

  vim.cmd("HopWord")

  -- Select jumped-to word
  vim.cmd("normal! viw")
end

map({ "n", "x", "o" }, "f", hop_word_select, {
  desc = "Jump and select word",
})

vim.keymap.set({ "n", "x", "o" }, "F", "<cmd>HopChar1<CR>", {
  desc = "Hop to char",
})

-- Window switching

vim.pack.add({
  {
    src = "https://github.com/s1n7ax/nvim-window-picker",
    version = vim.version.range("2.*"),
  },
})

require("window-picker").setup({
  hint = "floating-big-letter",

  filter_rules = {
    include_current_win = false,
    autoselect_one = true,
    include_unfocusable_windows = true,

    bo = {
      filetype = { "notify" },
      buftype = { "terminal" },
    },
  },
})

-- Pick window
vim.keymap.set("n", "<D-.>", function()
  local win = require("window-picker").pick_window()

  if win then
    vim.api.nvim_set_current_win(win)
  end
end, {
  desc = "Pick window",
})


-- Helix like approach to get an object first
-- vim.pack.add({ "https://github.com/luiscassih/AniMotion.nvim" })
--
--
-- local Utils = require("AniMotion.Utils")
--
-- require("AniMotion").setup({
--   mode = "animotion", -- "nvim" or "helix"
--   word_keys = {
--     [Utils.Targets.NextWordStart] = "w",
--     [Utils.Targets.NextWordEnd] = "j",
--     [Utils.Targets.PrevWordStart] = "b",
--
--     [Utils.Targets.NextLongWordStart] = "W",
--     [Utils.Targets.NextLongWordEnd] = "J",
--     [Utils.Targets.PrevLongWordStart] = "B",
--   },
--   edit_keys = { "c", "d", "s", "r", "y" }, -- you can add "p" if you want.
--   clear_keys = { "<Esc>" },                -- used when you want to deselect/exit from SEL mode.
--   marks = { "y", "z" },                    -- Is a mark used internally in this plugin, when we do a visual select when changing or deleting the highlighted word.
--   map_visual = true,                       -- When true, we capture "v" and pressing it will enter visual mode with the plugin selection as part of the visual selection. When false, pressing "v" will exit SEL mode and the selection will be lost. You want to set to false if you have trouble with other mappings associated to "v". I recommend to try in true first.
--   color = { bg = "#673AB7" }               -- put color = "Visual" to use the default visual mode color. You can also customize via vim.api.nvim_set_hl(0, "@AniMotion", hl_color)
-- })
--
vim.pack.add({
  "https://github.com/mirlge/kak.nvim",
})


local map = vim.keymap.set

-- require("kak").setup({
--   full = true,
-- })

-- local function get_map(mode, lhs)
--   local mapping = vim.fn.maparg(lhs, mode, false, true)

--   if vim.tbl_isempty(mapping) then
--     error(("No mapping for %s in mode %s"):format(lhs, mode))
--   end

--   return mapping.callback or mapping.rhs
-- end

-- -- Save Kak word selections before overriding keys
-- local kak_word_end = get_map("n", "e")
-- local kak_WORD_end = get_map("n", "E")

-- -- Colemak navigation
-- map({ "n", "x" }, "n", "gj", { desc = "Down" })
-- map({ "n", "x" }, "e", "gk", { desc = "Up" })
-- map({ "n", "x" }, "i", "l", { desc = "Right" })

-- -- Kak word selection on your keys
-- map("n", "j", kak_word_end, { desc = "Select word end" })
-- map("n", "J", kak_WORD_end, { desc = "Select WORD end" })

-- -- Continue/adjust selection in Visual mode
-- map("x", "j", "e", { desc = "Word end" })
-- map("x", "J", "E", { desc = "WORD end" })

-- -- Search navigation
-- map({ "n", "x" }, "k", "n", { desc = "Next search result" })
-- map({ "n", "x" }, "K", "N", { desc = "Previous search result" })

-- -- Insert
-- map("n", "l", "i", { desc = "Insert" })
-- map("n", "L", "I", { desc = "Insert at line start" })

-- -- Restore end of buffer
-- -- Restore native G
-- pcall(vim.keymap.del, "n", "G")
-- pcall(vim.keymap.del, "x", "G")

-- -- Release f for Hop
-- pcall(vim.keymap.del, "n", "f")
-- pcall(vim.keymap.del, "x", "f")
-- pcall(vim.keymap.del, "o", "f")




local function leave_selection()
  if vim.fn.mode():match("[vV\22]") then
    vim.cmd("normal! \27")
  end
end

local function select_next_word()
  leave_selection()

  -- Move exactly like native Vim `w`
  vim.cmd("normal! w")

  -- Select object under cursor
  vim.cmd("normal! viw")
end

-- Next word as a new selection
map({ "n", "x" }, "w", select_next_word, {
  desc = "Select next word",
})

-- Expand syntax selection
map("x", "W", function()
  vim.treesitter.select("parent")
end, {
  desc = "Expand selection",
})

-- Shrink syntax selection
map("x", "B", function()
  vim.treesitter.select("child")
end, {
  desc = "Shrink selection",
})

-- Enter selection
map("n", "x", "V", {
  desc = "Select",
})

-- Delete character
map("n", "d", "x", {
  desc = "Delete character",
})
