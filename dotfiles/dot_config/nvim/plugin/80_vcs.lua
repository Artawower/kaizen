-- Packages
vim.pack.add({
  "https://github.com/z4p5a9/blamer.nvim",
  "https://github.com/mistweaverco/jujutsu.nvim",
  { src = "https://github.com/nvim-mini/mini.diff" },
  "https://github.com/rafikdraoui/jj-diffconflicts",
  "https://github.com/madmaxieee/unclash.nvim",
  "https://github.com/NicolasGB/jj.nvim",
  "https://github.com/CoreyKaylor/diffbandit.nvim",
})

local map = vim.keymap.set

-- Blame            

vim.g.blamer_enabled = true

-- Jujutsu          

local jj = require("jujutsu")

jj.setup({
  kind = "tab",
  mappings = {
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
    diffview = nil,
    codediff = nil,
  },
  diff_viewer = nil,
  file_history = { limit = 200, panel_height = 16 },
  annotate = { panel_height = 16 },
  disable_signs = true,
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
  commit_date_format = "absolute",
  log_date_format = "absolute",
})

map("n", "<leader>vl", jj.open, { desc = "Open version control log" })
map("n", "<leader>vm", jj.action("change", "commit"), { desc = "JJ commit" })
map("n", "<leader>vc", function()
  require("jj.picker").status()
end, { desc = "JJ changed files" })
map("n", "<leader>vb", jj.annotate)
map("n", "<leader>vr", jj.review)
map("n", "<leader>vg", jj.forge_popup)
map("n", "<leader>vi", jj.issue_panel)

-- Jujutsu picker   

require("jj-diffconflicts")
require("jj").setup({
  picker = {
    snacks = {
      auto_close = false,

      jump = {
        close = false,
      },
      layout = {
        preset = "sidebar",
        preview = "main",

        layout = {
          position = "left",
          width = 35,
        },
      },
    },
  },
})



-- Diff gutters     

local diff = require("mini.diff")

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

-- Diff bandit      

require("diffbandit").setup()
