local map = vim.keymap.set

vim.g.blamer_enabled = true

vim.pack.add({
  {
    src = "https://github.com/z4p5a9/blamer.nvim",
    data = {
      cmd = { "BlamerToggle", "BlamerEnable", "BlamerDisable" },
      event = { "CursorMoved", "CursorMovedI" },
      after = function()
        if vim.g.blamer_enabled then
          vim.fn["blamer#BufferEnter"]()
          vim.fn["blamer#Refresh"]()
        end
      end,
    },
  },
  {
    src = "https://github.com/mistweaverco/jujutsu.nvim",
    data = {
      cmd = { "J", "Jujutsu" },
      after = function()
        require("jujutsu").setup({
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
      end,
    },
  },
  { src = "https://github.com/rafikdraoui/jj-diffconflicts" },
  { src = "https://github.com/NicolasGB/jj.nvim" },
  {
    src = "https://github.com/nvim-mini/mini.diff",
    data = {
      event = { "BufReadPost", "BufNewFile" },
      after = function()
        require("mini.diff").setup({
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
      end,
    },
  },
  {
    src = "https://github.com/CoreyKaylor/diffbandit.nvim",
    data = {
      cmd = {
        "DiffBandit",
        "DiffBanditBuffers",
        "DiffBanditGit",
        "DiffBanditGitCurrent",
        "DiffBanditCommitPanel",
        "DiffBanditGitMenu",
        "DiffBanditGitLog",
        "DiffBanditGitCommit",
        "DiffBanditGitCompare",
        "DiffBanditGitCheckout",
        "DiffBanditMerge",
        "DiffBanditFolderDiff",
      },
      after = function()
        require("diffbandit").setup({
          ui = {
            theme = {
              highlights = {
                DiffBanditContext = { bg = "NONE" },
                DiffBanditSignColumn = { bg = "NONE" },
                DiffBanditSplit = { link = "WinSeparator" },
                DiffBanditStatus = { link = "StatusLine" },
                DiffBanditStatusLine = { link = "StatusLine" },
                DiffBanditStatusAccent = { link = "Identifier" },
                DiffBanditStatusMuted = { link = "StatusLineNC" },
                DiffBanditGap = { link = "Comment" },
                DiffBanditPlaceholder = { link = "Comment" },
                DiffBanditEmptyNotice = { link = "Comment" },
                DiffBanditConnectorContext = { link = "Comment" },
                DiffBanditOverviewContext = { bg = "NONE", fg = "NONE" },
              },
            },
          },
        })
      end,
    },
  },
  {
    src = "https://github.com/madmaxieee/unclash.nvim",
    data = {
      cmd = "Unclash",
    },
  },
}, { load = require("lz.n").load })

map("n", "<leader>vB", function()
  local initialized = vim.g.blamer_is_initialized == 1
  require("lz.n").trigger_load("blamer.nvim")
  if initialized then
    vim.cmd.BlamerToggle()
  end
end, {
  desc = "Toggle inline Git blame",
})

local function jj()
  require("lz.n").trigger_load("jujutsu.nvim")
  return require("jujutsu")
end

map("n", "<leader>vl", function()
  jj().open()
end, { desc = "Open version control log" })

map("n", "<leader>vm", function()
  jj().action("change", "commit")()
end, { desc = "JJ commit" })

map("n", "<leader>vc", function()
  jj()
  require("jj.picker").status()
end, { desc = "JJ changed files" })

map("n", "<leader>vb", function()
  jj().annotate()
end, { desc = "JJ annotate" })

map("n", "<leader>vr", function()
  jj().review()
end, { desc = "JJ review" })

map("n", "<leader>vg", function()
  jj().forge_popup()
end, { desc = "JJ forge" })

map("n", "<leader>vi", function()
  jj().issue_panel()
end, { desc = "JJ issues" })

local function diff()
  require("lz.n").trigger_load("mini.diff")
  return require("mini.diff")
end

vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
  callback = function(args)
    diff().enable(args.buf)
  end,
})

map("n", "]g", function()
  diff().goto_hunk("next")
end, {
  desc = "Next git hunk",
})

map("n", "[g", function()
  diff().goto_hunk("prev")
end, {
  desc = "Previous git hunk",
})

map("n", "<leader>gp", function()
  diff().toggle_overlay()
end, {
  desc = "Toggle git diff",
})

map("n", "<leader>gr", function()
  local d = diff()
  local bufnr = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local data = d.get_buf_data(bufnr)

  if not data then
    return
  end

  local hunk
  for _, item in ipairs(data.hunks) do
    local first = math.max(item.buf_start, 1)
    local last = first + math.max(item.buf_count, 1) - 1
    if line >= first and line <= last then
      hunk = item
      break
    end
  end

  if not hunk then
    vim.notify("No git hunk under cursor")
    return
  end

  local overlay_was_open = data.overlay
  if not overlay_was_open then
    d.toggle_overlay(bufnr)
  end

  vim.schedule(function()
    vim.ui.select({ "Reset", "Cancel" }, {
      prompt = "Discard this hunk?",
    }, function(choice)
      if choice == "Reset" then
        local first = math.max(hunk.buf_start, 1)
        local last = first + math.max(hunk.buf_count, 1) - 1
        d.do_hunks(bufnr, "reset", {
          line_start = first,
          line_end = last,
        })
      end

      if not overlay_was_open then
        d.toggle_overlay(bufnr)
      end
    end)
  end)
end, {
  desc = "Reset git hunk",
})
