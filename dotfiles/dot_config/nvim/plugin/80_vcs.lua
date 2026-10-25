local map = require("helpers").map

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

map("n", { "<leader>vB", "<leader>мИ" }, function()
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

map("n", { "<leader>vl", "<leader>мг" }, function()
  jj().open()
end, { desc = "Open version control log" })


map("n", { "<leader>vh", "<leader>мр" }, function()
  jj().open()
end, { desc = "Open version control history" })

map("n", { "<leader>vm", "<leader>мь" }, function()
  jj().action("change", "commit")()
end, { desc = "JJ commit" })

map("n", { "<leader>vc", "<leader>мс" }, function()
  jj()
  require("jj.picker").status()
end, { desc = "JJ changed files" })

map("n", { "<leader>vb", "<leader>ми" }, function()
  jj().annotate()
end, { desc = "JJ annotate" })

map("n", { "<leader>vr", "<leader>мы" }, function()
  jj().review()
end, { desc = "JJ review" })

map("n", { "<leader>vg", "<leader>ме" }, function()
  jj().forge_popup()
end, { desc = "JJ forge" })

map("n", { "<leader>vi", "<leader>мд" }, function()
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

map("n", { "<leader>gp", "<leader>ек" }, function()
  diff().toggle_overlay()
end, {
  desc = "Toggle git diff",
})

map("n", { "<leader>gr", "<leader>еы" }, function()
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


-- Github review
--
vim.pack.add({
  "https://github.com/zion-off/diff"
})


require("diff").setup({
  -- Sidebar position: "left" (default) or "right"
  sidebar_position = "left",

  -- Sidebar width in columns (default: 40)
  sidebar_width = 40,

  -- Notes panel width in columns (default: 40)
  notes_width = 40,

  -- Auto-refresh panels on FocusGained / BufWritePost (default: true)
  -- Also watches .git/index via libuv fs_event for immediate refresh.
  auto_refresh = true,

  -- Branch mode compares the branch against this branch (default: nil, which
  -- uses the remote's default branch origin/HEAD, else a local main or master).
  base_branch = nil,

  -- Mouse interactivity in the sidebar (default: true). Clicking a file opens
  -- its diff; clicking a commit expands/collapses it; clicking a section header
  -- toggles it. Hovering tints whatever a click would act on (rows, "hidden
  -- lines" separators) and highlights the window edge you can drag to resize
  -- (edges need Neovim 0.11+).
  -- Only enables Neovim's 'mouse' option while the interface is open, and
  -- 'mousemoveevent' only while its tab is the current one, restoring both.
  -- With 'mousemoveevent' on, moving the mouse in the middle of a key
  -- sequence (after <leader>, say) cancels it.
  mouse = true,

  -- Lines of context around each change (nil shows whole files).
  context_lines = 3,

  -- Soft-wrap long lines in the diff panes (default: true). In the split view
  -- the shorter side of each row is padded to the taller side's height, so the
  -- panes stay aligned while scrolling. Split panes narrower than 20 text
  -- columns scroll horizontally instead. Needs Neovim 0.10+ in the split view;
  -- on 0.9 split panes stay unwrapped.
  wrap = true,

  -- Log verbosity: "trace" | "debug" | "info" | "warn" (default) | "error" | "off".
  -- The log lives at stdpath("log")/diff.nvim.log; open it with :DiffNvimLog.
  log_level = "warn",

  -- Keybinding overrides (set any to false/"" to disable)
  keymaps = {
    toggle_sidebar       = "<leader>gs",
    toggle_sidebar_panel = "<leader>gS",
    copy_notes_path      = "<leader>gy",
    open_diff            = "<CR>",
    stage_file           = "s",
    unstage_file         = "u",
    collapse             = "z",
    next_hunk            = "]c",
    prev_hunk            = "[c",
    next_file            = "]f",
    prev_file            = "[f",
    goto_file            = "gf",
    stage_hunk           = "s",
    unstage_hunk         = "u",
    leave_note           = "<leader>n",
    toggle_notes         = "<leader>N",
    preview_branch       = "<leader>gb",
    branch_changes       = "<leader>gB",
    expand_context       = "zo",
    expand_all           = "zR",
    collapse_all         = "zM",
    commit_tooltip       = "K",
  },

  -- Highlight colour overrides — any valid :hi attribute table
  highlights = {
    -- e.g. { bg = "#0d1f0d" }
  },
})
