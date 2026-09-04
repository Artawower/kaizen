local map = vim.keymap.set;

vim.pack.add({ "https://github.com/z4p5a9/blamer.nvim" })

vim.g.blamer_enabled = true;


-- Jujutsu


vim.pack.add({ "https://github.com/mistweaverco/jujutsu.nvim" })


local jj = require("jujutsu")

jj.setup({
  kind = "tab", -- tab | split | vsplit | floating | replace | auto | ...
  mappings = {
    -- set a key to false to disable a default
    status = {
      ["q"] = "Close",
      ["x"] = "Discard",
    },
    popup = {
      ["c"] = "ChangePopup",
      ["b"] = "BookmarkPopup",
    },
  },
  integrations = {
    -- nil = auto-detect, true = force, false = disable
    diffview = nil,
    codediff = nil,
  },
  diff_viewer = nil, -- "diffview" | "codediff" | nil = auto
  file_history = { limit = 200, panel_height = 16 },
  annotate = { panel_height = 16 },
  disable_signs = true, -- gutter jjsigns (add/change/delete)
  signs = {
    item = { ">", "v" },
    section = { ">", "v" },
    add = { text = "┃" },
    change = { text = "┃" },
    delete = { text = "▁" },
    topdelete = { text = "▔" },
    changedelete = { text = "~" },
  },
  forge = { pr_integration = true },
  commit_date_format = "absolute", -- "absolute" | "relative" | strftime (e.g. "%Y-%m-%d %H:%M")
  log_date_format = "absolute",
})

-- Bindable action for your own keymaps:
map("n", "<leader>vl", jj.open, { desc = "Open version control log" })
map("n", "<leader>vc", jj.action("change", "commit"))
map("n", "<leader>vb", jj.annotate)
map("n", "<leader>vr", jj.review)
map("n", "<leader>vg", jj.forge_popup)
map("n", "<leader>vi", jj.issue_panel)


-- Gutters
vim.pack.add({
  { src = "https://github.com/nvim-mini/mini.diff" },
})

local diff = require("mini.diff")
local map = vim.keymap.set

diff.setup({
  view = {
    style = "sign",
    signs = {
      add = "┃",
      change = "┃",
      delete = "▁",
    },
  },

  mappings = {
    apply = "",
    reset = "",
    textobject = "gh",

    goto_first = "",
    goto_prev = "",
    goto_next = "",
    goto_last = "",
  },
})

-- Git hunk navigation
map("n", "]g", function()
  diff.goto_hunk("next")
end, {
  desc = "Next git hunk",
})

map("n", "[g", function()
  diff.goto_hunk("prev")
end, {
  desc = "Previous git hunk",
})

-- Diff overlay
map("n", "<leader>gp", function()
  diff.toggle_overlay()
end, {
  desc = "Toggle git diff",
})


-- Reset current hunk
map("n", "<leader>gr", function()
  local bufnr = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1]

  local data = diff.get_buf_data(bufnr)

  if not data then
    return
  end

  local hunk

  for _, h in ipairs(data.hunks) do
    local first = math.max(h.buf_start, 1)
    local last = first + math.max(h.buf_count, 1) - 1

    if line >= first and line <= last then
      hunk = h
      break
    end
  end

  if not hunk then
    vim.notify("No git hunk under cursor")
    return
  end

  local overlay_was_open = data.overlay

  if not overlay_was_open then
    diff.toggle_overlay(bufnr)
  end

  vim.schedule(function()
    vim.ui.select(
      { "Reset", "Cancel" },
      {
        prompt = "Discard this hunk?",
      },
      function(choice)
        if choice == "Reset" then
          local first = math.max(hunk.buf_start, 1)
          local last = first + math.max(hunk.buf_count, 1) - 1

          diff.do_hunks(bufnr, "reset", {
            line_start = first,
            line_end = last,
          })
        end

        if not overlay_was_open then
          diff.toggle_overlay(bufnr)
        end
      end
    )
  end)
end, {
  desc = "Reset git hunk",
})

-- Jujutsu cinflicts
vim.pack.add({
  "https://github.com/rafikdraoui/jj-diffconflicts",
  "https://github.com/madmaxieee/unclash.nvim",
  "https://github.com/NicolasGB/jj.nvim"
})

require("jj-diffconflicts")
require("jj").setup({})

local jj_picker = require("jj.picker")

map("n", "<leader>jc", function()
  jj_picker.conflict_sections()
end, {
  desc = "JJ conflicts",
})

-- Zdiff
vim.pack.add({ "https://github.com/CoreyKaylor/diffbandit.nvim" })
require("diffbandit").setup()
